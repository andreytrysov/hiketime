import Foundation
import HikeTimeCore

/// Тайлы terrarium по сети с кэшем в памяти и на диске.
/// В нативе нет CORS — читаем пиксели напрямую, костыль веб-версии не нужен.
/// Оффлайн-пакеты района — следующий шаг, интерфейс уже готов к подмене.
actor TileStore {

    private var tiles: [DEM.TileKey: DEM.Tile] = [:]
    private let session = URLSession(configuration: .default)
    private let diskDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("terrarium", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Скачивает недостающие тайлы и отдаёт снимок — синхронному
    /// RouteBuilder не нужен доступ в актор.
    func tilesFor(points: [GeoPoint], zoom: Int) async throws -> [DEM.TileKey: DEM.Tile] {
        var needed = Set<DEM.TileKey>()
        for p in points {
            let g = DEM.toGlobalPixels(lat: p.lat, lon: p.lon, zoom: zoom)
            let fx = g.x - 0.5, fy = g.y - 0.5
            for ox in 0...1 {
                for oy in 0...1 {
                    let gx = Int(fx.rounded(.down)) + ox
                    let gy = Int(fy.rounded(.down)) + oy
                    needed.insert(DEM.TileKey(z: zoom, x: gx / 256, y: gy / 256))
                }
            }
        }
        for key in needed where tiles[key] == nil {
            tiles[key] = try await load(key)
        }
        return tiles.filter { needed.contains($0.key) }
    }

    private func load(_ key: DEM.TileKey) async throws -> DEM.Tile {
        let file = diskDir.appendingPathComponent("\(key.z)_\(key.x)_\(key.y).png")
        if let data = try? Data(contentsOf: file), let t = DEM.Tile(pngData: data) {
            return t
        }
        let url = URL(string:
            "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(key.z)/\(key.x)/\(key.y).png")!
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let tile = DEM.Tile(pngData: data) else {
            throw DEM.DEMError.tileUnavailable(key)
        }
        try? data.write(to: file)
        return tile
    }
}
