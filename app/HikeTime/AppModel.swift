import Foundation
import SwiftUI
import HikeTimeCore

/// Состояние приложения: маршрут, настройки, расчёт.
/// Вся математика — в HikeTimeCore, сверенном с прототипами.
@MainActor
final class AppModel: ObservableObject {

    // маршрут
    @Published var path: [GeoPoint] = []
    @Published var profile: RouteProfile?
    @Published var computing = false
    @Published var elevationError = false
    private var history: [[GeoPoint]] = []

    // настройки (переживают перезапуск)
    @AppStorage("loadKg") var loadKg: Double = 10 { didSet { recomputeTime() } }
    @AppStorage("bodyKg") var bodyKg: Double = 75 { didSet { recomputeTime() } }
    @AppStorage("power") var power: Double = 3.6 { didSet { recomputeTime() } }
    @AppStorage("terrain") var terrain: Double = 1.0 { didSet { recomputeTime() } }

    // режимы
    @Published var drawMode = false
    @Published var eraseMode = false

    // результат
    @Published var totalText = "—"
    @Published var movingText = ""
    @Published var breaksText = ""
    @Published var statsText = ""
    @Published var sensText = ""

    private let dem = TileStore()
    private var computeTask: Task<Void, Never>?

    var hasRoute: Bool { path.count >= 2 }

    // MARK: правки

    func pushHistory() {
        history.append(path)
        if history.count > 40 { history.removeFirst() }
    }

    func undo() {
        guard let prev = history.popLast() else { clear(); return }
        path = prev
        path.count >= 2 ? recomputeProfile() : clear()
    }

    func clear() {
        path = []
        history = []
        profile = nil
        totalText = "—"
        movingText = ""; breaksText = ""; statsText = ""; sensText = ""
    }

    // MARK: расчёт

    func recomputeProfile() {
        guard path.count >= 2 else { return }
        let snapshot = path
        computing = true
        elevationError = false
        computeTask?.cancel()
        computeTask = Task { [dem] in
            do {
                let prof = try await Self.buildProfile(points: snapshot, store: dem)
                guard !Task.isCancelled else { return }
                self.profile = prof
                self.computing = false
                self.recomputeTime()
            } catch {
                guard !Task.isCancelled else { return }
                self.computing = false
                self.elevationError = true
            }
        }
    }

    nonisolated private static func buildProfile(points: [GeoPoint],
                                                 store: TileStore) async throws -> RouteProfile {
        // высоты тянутся заранее и асинхронно, сам конвейер синхронный
        let dense = Geo.resample(points, step: 25)
        let tiles = try await store.tilesFor(points: dense, zoom: 12)
        return try RouteBuilder.build(points: points) { key in
            guard let t = tiles[key] else { throw DEM.DEMError.tileUnavailable(key) }
            return t
        }
    }

    func recomputeTime() {
        guard let prof = profile else { return }
        let model = EnergyModel(bodyKg: bodyKg, loadKg: loadKg,
                                powerPerKg: power, terrain: terrain)
        let moving = model.timeHours(prof.segments)
        let br = Breaks(movingHours: moving)
        totalText = Self.fmt(br.totalHours)
        movingText = "в движении \(Self.fmt(moving))"
        breaksText = br.shortBreaks > 0
            ? "привалы \(br.shortBreaks) × 10 мин" + (br.lunchMinutes > 0 ? " · обед 30 мин" : "")
            : "без привалов"
        let pace = moving > 0 ? prof.distM / 1000 / moving : 0
        statsText = String(format: "%.1f км · ↑%.0f м · ↓%.0f м · %.1f км/ч",
                           prof.distM / 1000, prof.gainM, prof.lossM, pace)
        var plusOne = model
        plusOne.loadKg += 1
        let dMin = (plusOne.timeHours(prof.segments) - moving) * 60
        sensText = String(format: "+1 кг = +%.0f мин", dMin)
    }

    nonisolated private static func fmt(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    // строка зоны нагрузки — та же логика, что в прототипе
    var loadZone: (Color, String) {
        let p = loadKg / bodyKg * 100
        switch p {
        case ..<10: return (.green, String(format: "%.0f%% массы тела — вес почти не мешает", p))
        case ..<20: return (.green, String(format: "%.0f%% массы тела — нормальная многодневка", p))
        case ..<25: return (.orange, String(format: "%.0f%% массы тела — тяжело, риск растёт", p))
        case ..<30: return (.red, String(format: "%.0f%% массы тела — расход выше на треть", p))
        default: return (.red, String(format: "%.0f%% массы тела — так ходить не надо", p))
        }
    }
}
