import Foundation
import HikeTimeCore

/// Сохранённые маршруты: JSON-файл в Documents. Локально, как в прототипе;
/// облачная синхронизация — Pro-фича из плана монетизации.
struct SavedRoute: Codable, Identifiable, Equatable {
    let id: Double
    var name: String
    let ts: Date
    let path: [[Double]]          // [lat, lon]
    let loadKg: Double
    let terrain: Double
    let power: Double
    let distM: Double
    let timeText: String
}

@MainActor
final class RoutesStore: ObservableObject {
    @Published private(set) var routes: [SavedRoute] = []

    private let file: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("routes.json")
    }()

    init() {
        if let data = try? Data(contentsOf: file),
           let list = try? JSONDecoder().decode([SavedRoute].self, from: data) {
            routes = list
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(routes) {
            try? data.write(to: file)
        }
    }

    @discardableResult
    func add(name: String, path: [GeoPoint], loadKg: Double, terrain: Double,
             power: Double, distM: Double, timeText: String) -> SavedRoute {
        let r = SavedRoute(id: Date().timeIntervalSince1970, name: name, ts: Date(),
                           path: path.map { [$0.lat, $0.lon] },
                           loadKg: loadKg, terrain: terrain, power: power,
                           distM: distM, timeText: timeText)
        routes.insert(r, at: 0)
        if routes.count > 50 { routes.removeLast() }
        persist()
        return r
    }

    func delete(_ r: SavedRoute) {
        routes.removeAll { $0.id == r.id }
        persist()
    }
}

/// Ссылка «поделиться» — тот же формат, что у веб-прототипа:
/// получатель без приложения откроет маршрут в браузере.
enum RouteShare {
    static let webBase = "https://andreytrysov.github.io/hiketime/"

    static func encodePolyline(_ path: [GeoPoint]) -> String {
        var out = ""
        var pLat = 0, pLng = 0
        func enc(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : value << 1
            while v >= 0x20 {
                out.append(Character(UnicodeScalar((0x20 | (v & 0x1f)) + 63)!))
                v >>= 5
            }
            out.append(Character(UnicodeScalar(v + 63)!))
        }
        for p in path {
            let la = Int((p.lat * 1e5).rounded())
            let ln = Int((p.lon * 1e5).rounded())
            enc(la - pLat); enc(ln - pLng)
            pLat = la; pLng = ln
        }
        return out
    }

    static func url(path: [GeoPoint], loadKg: Double,
                    terrain: Double, power: Double) -> URL {
        let poly = encodePolyline(path)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: webBase +
            "#r=\(poly)&w=\(Int(loadKg))&t=\(terrain)&p=\(power)")!
    }
}
