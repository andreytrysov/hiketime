import Foundation
import HikeTimeCore

/// Скачанный район: тайлы рельефа + посчитанные по ним горизонтали.
/// Тайлы лежат в общей папке (ключ z/x/y глобальный), поэтому соседние
/// районы переиспользуют общие тайлы, а при удалении сносится только то,
/// что больше никому не нужно.
struct Region: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let created: Date
    let minLat, minLon, maxLat, maxLon: Double
    let tiles: [String]            // "z/x/y"
    let bytes: Int
}

@MainActor
final class RegionStore: ObservableObject {
    @Published private(set) var regions: [Region] = []
    @Published var progress: Double?        // 0...1, пока идёт скачивание
    @Published var lastError: String?

    static let zoom = 12                    // выше DEM не детальнее

    private let root: URL = {
        let d = FileManager.default.urls(for: .documentDirectory,
                                         in: .userDomainMask)[0]
        return d
    }()
    var tilesDir: URL { root.appendingPathComponent("tiles/terrarium") }
    var vectorDir: URL { root.appendingPathComponent("tiles/vector") }
    /// есть ли распакованный векторный пакет — от этого зависит,
    /// показывать ли подложку «Топо (оффлайн)»
    var hasVectorTiles: Bool {
        FileManager.default.fileExists(atPath: vectorDir.path)
    }
    var contoursURL: URL { root.appendingPathComponent("contours.geojson") }
    private var metaURL: URL { root.appendingPathComponent("regions.json") }

    init() {
        try? FileManager.default.createDirectory(at: tilesDir,
                                                 withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: metaURL),
           let list = try? JSONDecoder().decode([Region].self, from: d) {
            regions = list
        }
        if regions.isEmpty { seedFromBundle() }
    }

    var totalBytes: Int { regions.reduce(0) { $0 + $1.bytes } }

    /// Первый запуск: переносим вшитый демо-район, чтобы приложение
    /// работало из коробки и стиль всегда имел куда смотреть.
    private func seedFromBundle() {
        guard let bundled = Bundle.main.resourceURL?
                .appendingPathComponent("Tiles/terrarium"),
              FileManager.default.fileExists(atPath: bundled.path) else { return }
        var keys: [String] = []
        var bytes = 0
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        let fm = FileManager.default
        for zDir in (try? fm.contentsOfDirectory(atPath: bundled.path)) ?? [] {
            guard let z = Int(zDir) else { continue }
            let zPath = bundled.appendingPathComponent(zDir)
            for xDir in (try? fm.contentsOfDirectory(atPath: zPath.path)) ?? [] {
                guard let x = Int(xDir) else { continue }
                let xPath = zPath.appendingPathComponent(xDir)
                for yFile in (try? fm.contentsOfDirectory(atPath: xPath.path)) ?? [] {
                    guard let y = Int(yFile.replacingOccurrences(of: ".png", with: ""))
                    else { continue }
                    let src = xPath.appendingPathComponent(yFile)
                    let dst = tilesDir.appendingPathComponent("\(z)/\(x)")
                    try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
                    let target = dst.appendingPathComponent("\(y).png")
                    if !fm.fileExists(atPath: target.path) {
                        try? fm.copyItem(at: src, to: target)
                    }
                    bytes += (try? Data(contentsOf: target).count) ?? 0
                    keys.append("\(z)/\(x)/\(y)")
                    let b = Self.tileBounds(z: z, x: x, y: y)
                    minLat = min(minLat, b.minLat); maxLat = max(maxLat, b.maxLat)
                    minLon = min(minLon, b.minLon); maxLon = max(maxLon, b.maxLon)
                }
            }
        }
        guard !keys.isEmpty else { return }
        regions = [Region(id: UUID().uuidString, name: "Zermatt",
                          created: Date(), minLat: minLat, minLon: minLon,
                          maxLat: maxLat, maxLon: maxLon,
                          tiles: keys, bytes: bytes)]
        persist()
        // горизонтали для демо уже вшиты — копируем как есть
        if let src = Bundle.main.resourceURL?
            .appendingPathComponent("Tiles/contours.geojson"),
           !FileManager.default.fileExists(atPath: contoursURL.path) {
            try? FileManager.default.copyItem(at: src, to: contoursURL)
        }
    }

    // MARK: скачивание

    struct Plan {
        let tiles: [(z: Int, x: Int, y: Int)]
        var count: Int { tiles.count }
        var estimateMB: Double { Double(count) * 0.11 }   // ~110 КБ на тайл
    }

    static func plan(minLat: Double, minLon: Double,
                     maxLat: Double, maxLon: Double) -> Plan {
        let z = zoom
        let (x0, y0) = tileIndex(lat: maxLat, lon: minLon, z: z)
        let (x1, y1) = tileIndex(lat: minLat, lon: maxLon, z: z)
        var list: [(Int, Int, Int)] = []
        for x in min(x0, x1)...max(x0, x1) {
            for y in min(y0, y1)...max(y0, y1) {
                list.append((z, x, y))
            }
        }
        return Plan(tiles: list)
    }

    func download(name: String, minLat: Double, minLon: Double,
                  maxLat: Double, maxLon: Double) async {
        let plan = Self.plan(minLat: minLat, minLon: minLon,
                             maxLat: maxLat, maxLon: maxLon)
        progress = 0
        lastError = nil
        var keys: [String] = []
        var bytes = 0
        let fm = FileManager.default

        for (i, t) in plan.tiles.enumerated() {
            let key = "\(t.z)/\(t.x)/\(t.y)"
            let dir = tilesDir.appendingPathComponent("\(t.z)/\(t.x)")
            let file = dir.appendingPathComponent("\(t.y).png")
            if !fm.fileExists(atPath: file.path) {
                let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(key).png")!
                do {
                    let (data, resp) = try await URLSession.shared.data(from: url)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        continue                       // дырка в покрытии — не беда
                    }
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try data.write(to: file)
                } catch {
                    lastError = error.localizedDescription
                    progress = nil
                    return
                }
            }
            bytes += (try? Data(contentsOf: file).count) ?? 0
            keys.append(key)
            progress = Double(i + 1) / Double(plan.count)
        }

        regions.append(Region(id: UUID().uuidString, name: name,
                              created: Date(), minLat: minLat, minLon: minLon,
                              maxLat: maxLat, maxLon: maxLon,
                              tiles: keys, bytes: bytes))
        persist()
        await rebuildContours()
        progress = nil
    }

    func delete(_ r: Region) {
        regions.removeAll { $0.id == r.id }
        let stillUsed = Set(regions.flatMap { $0.tiles })
        let fm = FileManager.default
        for key in r.tiles where !stillUsed.contains(key) {
            try? fm.removeItem(at: tilesDir.appendingPathComponent(key + ".png"))
        }
        persist()
        Task { await rebuildContours() }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(regions) { try? d.write(to: metaURL) }
    }

    // MARK: горизонтали

    /// Пересобирает горизонтали по всем скачанным тайлам.
    func rebuildContours() async {
        let dir = tilesDir
        let out = contoursURL
        let all = Set(regions.flatMap { $0.tiles })
        guard !all.isEmpty else {
            try? FileManager.default.removeItem(at: out)
            return
        }
        await Task.detached(priority: .utility) {
            Self.writeContours(tiles: all, tilesDir: dir, to: out)
        }.value
    }

    nonisolated static func writeContours(tiles: Set<String>, tilesDir: URL,
                                          to out: URL) {
        // группируем по z, собираем сплошную сетку по каждой связной области
        var byZ: [Int: [(x: Int, y: Int)]] = [:]
        for key in tiles {
            let p = key.split(separator: "/").compactMap { Int($0) }
            guard p.count == 3 else { continue }
            byZ[p[0], default: []].append((p[1], p[2]))
        }
        var features: [String] = []
        for (z, list) in byZ {
            guard let x0 = list.map({ $0.x }).min(), let x1 = list.map({ $0.x }).max(),
                  let y0 = list.map({ $0.y }).min(), let y1 = list.map({ $0.y }).max()
            else { continue }
            let w = (x1 - x0 + 1) * 256, h = (y1 - y0 + 1) * 256
            guard w > 1, h > 1, w * h < 40_000_000 else { continue }
            var grid = [Double](repeating: -9999, count: w * h)
            for t in list {
                let url = tilesDir.appendingPathComponent("\(z)/\(t.x)/\(t.y).png")
                guard let data = try? Data(contentsOf: url),
                      let tile = DEM.Tile(pngData: data) else { continue }
                let ox = (t.x - x0) * 256, oy = (t.y - y0) * 256
                for py in 0..<256 {
                    for px in 0..<256 {
                        grid[(oy + py) * w + ox + px] = tile.at(px, py)
                    }
                }
            }
            let lines = Contours.build(grid: .init(values: grid, width: w, height: h))
            for line in lines {
                let coords = line.points.map { p -> String in
                    let gx = Double(x0 * 256) + p.0
                    let gy = Double(y0 * 256) + p.1
                    let ll = pixelToLonLat(gx: gx, gy: gy, z: z)
                    return "[\(String(format: "%.5f", ll.lon)),\(String(format: "%.5f", ll.lat))]"
                }.joined(separator: ",")
                features.append(
                    "{\"type\":\"Feature\",\"properties\":{\"ele\":\(Int(line.elevation)),"
                    + "\"major\":\(line.major ? 1 : 0)},"
                    + "\"geometry\":{\"type\":\"LineString\",\"coordinates\":[\(coords)]}}")
            }
        }
        let json = "{\"type\":\"FeatureCollection\",\"features\":[\(features.joined(separator: ","))]}"
        try? json.data(using: .utf8)?.write(to: out)
    }

    // MARK: тайловая арифметика

    static func tileIndex(lat: Double, lon: Double, z: Int) -> (Int, Int) {
        let n = pow(2.0, Double(z))
        let x = Int((lon + 180) / 360 * n)
        let latRad = lat * .pi / 180
        let y = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n)
        return (x, y)
    }

    static func tileBounds(z: Int, x: Int, y: Int)
        -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        func lat(_ yy: Int) -> Double {
            let n = Double.pi - 2 * .pi * Double(yy) / pow(2.0, Double(z))
            return 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
        }
        func lon(_ xx: Int) -> Double {
            Double(xx) / pow(2.0, Double(z)) * 360 - 180
        }
        return (lat(y + 1), lon(x), lat(y), lon(x + 1))
    }

    nonisolated static func pixelToLonLat(gx: Double, gy: Double, z: Int)
        -> (lon: Double, lat: Double) {
        let n = pow(2.0, Double(z)) * 256
        let lon = gx / n * 360 - 180
        let latRad = atan(sinh(.pi * (1 - 2 * gy / n)))
        return (lon, latRad * 180 / .pi)
    }
}
