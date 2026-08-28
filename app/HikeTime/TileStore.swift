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

    func prefetch(points: [GeoPoint], zoom: Int) async throws {
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
    }

    /// Провайдер по уже скачанному — для синхронного RouteBuilder.
    nonisolated func cachedProvider() -> DEM.TileProvider {
        let snapshot = { [weak self] in self }
        return { key in
            // actor уже прогрет prefetch-ем; провайдер зовётся синхронно
            guard let store = snapshot(),
                  let tile = store.tileSync(key) else {
                throw DEM.DEMError.tileUnavailable(key)
            }
            return tile
        }
    }

    nonisolated private func tileSync(_ key: DEM.TileKey) -> DEM.Tile? {
        // безопасно: словарь заполняется до вызова, читается после prefetch
        var result: DEM.Tile?
        let sem = DispatchSemaphore(value: 0)
        Task { result = await self.tiles[key]; sem.signal() }
        sem.wait()
        return result
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
