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

    // сохранение
    @Published var routeName: String?
    @Published var savedId: Double?

    // карта
    @AppStorage("baseLayer") var baseLayer: String = "hillshade"
    @Published var speedColor = false
    @Published var followUser = false
    /// счётчик запросов «подлететь к маршруту»
    @Published var fitRequest = 0

    // режимы
    @Published var drawMode = false
    @Published var eraseMode = false

    // взаимодействие
    @Published var sheetExpanded = false
    @Published var highlightIndex: Int?
    @Published var toastText: String?
    private var toastTask: Task<Void, Never>?

    func toast(_ text: String) {
        toastText = text          // ключ словаря; вью переводит при показе
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { self.toastText = nil }
        }
    }

    // результат
    @Published var totalText = "—"
    @Published var movingHoursText = ""
    @Published var shortBreaks = 0
    @Published var lunch = false
    @Published var statsText = ""
    @Published var sensMinutes = 0
    @Published var naiveText = ""
    @Published var gainMeters = 0.0
    @Published var lossMeters = 0.0
    @Published var paceKmh = 0.0
    /// накопленная дистанция по точкам профиля, км — ось X графика
    @Published var chartDistKm: [Double] = []

    private let dem = TileStore()
    private var computeTask: Task<Void, Never>?

    var hasRoute: Bool { path.count >= 2 }

    // MARK: правки

    func pushHistory() {
        history.append(path)
        if history.count > 40 { history.removeFirst() }
        savedId = nil                     // маршрут изменился
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
        routeName = nil
        savedId = nil
        totalText = "—"
        movingHoursText = ""; statsText = ""
        shortBreaks = 0; lunch = false; sensMinutes = 0
        naiveText = ""; gainMeters = 0; lossMeters = 0; paceKmh = 0
        chartDistKm = []
        highlightIndex = nil
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
        movingHoursText = Self.fmt(moving)
        shortBreaks = br.shortBreaks
        lunch = br.lunchMinutes > 0
        let pace = moving > 0 ? prof.distM / 1000 / moving : 0
        statsText = ""    // собирает вью через локализацию
        naiveText = Self.fmt(prof.distM / 1000 / 4)
        gainMeters = prof.gainM
        lossMeters = prof.lossM
        paceKmh = pace
        var cum = 0.0
        var dists = [0.0]
        for seg in prof.segments {
            cum += seg.distance
            dists.append(cum / 1000)
        }
        chartDistKm = dists
        var plusOne = model
        plusOne.loadKg += 1
        sensMinutes = Int(((plusOne.timeHours(prof.segments) - moving) * 60).rounded())
    }

    nonisolated private static func fmt(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    // цвет зоны нагрузки; текст собирает вью через локализацию
    var loadZone: (Color, String) {
        let p = loadKg / bodyKg * 100
        switch p {
        case ..<20: return (.green, "")
        case ..<25: return (.orange, "")
        default: return (.red, "")
        }
    }

    func statsLocalized(_ loc: Loc) -> String {
        guard let prof = profile else { return "" }
        let km = loc.t("единица_км"), m = loc.t("единица_м")
        return String(format: "%.1f %@ · ↑%.0f %@ · ↓%.0f %@",
                      prof.distM / 1000, km, prof.gainM, m, prof.lossM, m)
    }

    func breaksLocalized(_ loc: Loc) -> String {
        guard shortBreaks > 0 else { return loc.t("без привалов") }
        var out = "\(loc.t("привалы")) \(shortBreaks) × 10 \(loc.t("мин"))"
        if lunch { out += " · " + loc.t("обед 30 мин") }
        return out
    }
}
