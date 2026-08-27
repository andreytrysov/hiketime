// Верификатор без XCTest (Command Line Tools не дают его собрать).
// Гоняет те же проверки, что ReferenceTests: сверку с Python-эталоном.
import Foundation
import HikeTimeCore

struct Fixture: Codable {
    struct EnergyCase: Codable { let body, load, power, hours: Double }
    struct Classic: Codable { let naismith, din, munter, tobler: Double }
    let segments: [[Double]]
    let dist_m, gain_m, loss_m: Double
    let energy: [EnergyCase]
    let classic: Classic
    let minetti: [[Double]]
}

var failed = 0
func check(_ ok: Bool, _ label: String) {
    if ok { print("  ok  \(label)") }
    else { failed += 1; print("  FAIL \(label)") }
}
func near(_ a: Double, _ b: Double, rel: Double = 1e-3) -> Bool {
    abs(a - b) <= max(abs(b) * rel, 1e-9)
}

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let fixURL = root.appendingPathComponent(
    "Tests/HikeTimeCoreTests/Fixtures/reference.json")
let fix = try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixURL))
let segs = fix.segments.map { Segment(distance: $0[0], dh: $0[1]) }

print("кривая Minetti (21 точка):")
check(fix.minetti.allSatisfy { near(TimeModel.minettiCost($0[0]), $0[1], rel: 1e-4) },
      "совпадает с Python")
check(TimeModel.minettiCost(-0.10) < TimeModel.minettiCost(0),
      "пологий спуск дешевле ровного")

print("энергетическая модель (27 комбинаций тело × груз × мощность):")
var all = true
for c in fix.energy {
    let m = EnergyModel(bodyKg: c.body, loadKg: c.load, powerPerKg: c.power)
    if !near(m.timeHours(segs), c.hours) {
        all = false
        print("  расходится: body \(c.body) load \(c.load) power \(c.power)")
    }
}
check(all, "все 27 совпадают с Python в пределах 0.1%")

print("классические модели:")
check(near(ClassicModels.naismithLangmuir(distM: fix.dist_m, gainM: fix.gain_m,
                                          lossM: fix.loss_m, segments: segs),
           fix.classic.naismith), "Naismith+Langmuir")
check(near(ClassicModels.din33466(distM: fix.dist_m, gainM: fix.gain_m,
                                  lossM: fix.loss_m), fix.classic.din), "DIN 33466")
check(near(ClassicModels.munter(distM: fix.dist_m, gainM: fix.gain_m,
                                lossM: fix.loss_m), fix.classic.munter), "Мюнтер")
check(near(ClassicModels.tobler(segs), fix.classic.tobler), "Тоблер")

print("инварианты:")
check(EnergyModel(loadKg: 25).timeHours(segs) > EnergyModel(loadKg: 5).timeHours(segs),
      "тяжелее рюкзак — дольше")
check(EnergyModel(bodyKg: 95, loadKg: 20).timeHours(segs)
      < EnergyModel(bodyKg: 55, loadKg: 20).timeHours(segs),
      "те же 20 кг легче крупному")
let b = Breaks(movingHours: 5.0)
check(b.shortBreaks == 5 && b.lunchMinutes == 30, "привалы: 5×10 + обед на 5 ч хода")

let pts = [GeoPoint(lat: 45.98, lon: 7.70), GeoPoint(lat: 45.96, lon: 7.68)]
let dense = Geo.resample(pts, step: 25)
var sum = 0.0
for i in 1..<dense.count { sum += Geo.haversine(dense[i-1], dense[i]) }
check(near(sum, Geo.haversine(pts[0], pts[1]), rel: 1e-6), "ресемплинг держит длину")

print("DEM (реальный тайл z12 из фикстуры):")
struct DemFix: Codable {
    struct Case: Codable { let lat, lon, elev: Double }
    let zoom, tx, ty: Int
    let cases: [Case]
}
let demURL = root.appendingPathComponent("Tests/HikeTimeCoreTests/Fixtures/dem_reference.json")
let demFix = try! JSONDecoder().decode(DemFix.self, from: Data(contentsOf: demURL))
let tileURL = root.appendingPathComponent(
    "Tests/HikeTimeCoreTests/Fixtures/tile_\(demFix.zoom)_\(demFix.tx)_\(demFix.ty).png")
let tile = DEM.Tile(pngData: try! Data(contentsOf: tileURL))!
var demOK = true
for c in demFix.cases {
    let e = try! DEM.elevation(lat: c.lat, lon: c.lon, zoom: demFix.zoom) { key in
        guard key.x == demFix.tx, key.y == demFix.ty else {
            throw DEM.DEMError.tileUnavailable(key)
        }
        return tile
    }
    if abs(e - c.elev) > 0.05 {
        demOK = false
        print("  расходится: \(c.lat),\(c.lon): \(e) vs \(c.elev)")
    }
}
check(demOK, "5 высот совпадают с Python в пределах 5 см")

print("конвейер маршрута (5 точек -> профиль -> сводка):")
struct PipeFix: Codable {
    struct P: Codable { let lat, lon: Double }
    let waypoints: [P]
    let tiles: [[Int]]
    let dist_m, gain_m, loss_m: Double
    let n_points: Int
    let ele_first, ele_last: Double
}
let pipeURL = root.appendingPathComponent("Tests/HikeTimeCoreTests/Fixtures/pipeline_reference.json")
let pipe = try! JSONDecoder().decode(PipeFix.self, from: Data(contentsOf: pipeURL))
var tileCache: [DEM.TileKey: DEM.Tile] = [:]
let provider: DEM.TileProvider = { key in
    if let t = tileCache[key] { return t }
    let u = root.appendingPathComponent(
        "Tests/HikeTimeCoreTests/Fixtures/tile_\(key.z)_\(key.x)_\(key.y).png")
    guard let t = DEM.Tile(pngData: try Data(contentsOf: u)) else {
        throw DEM.DEMError.tileUnavailable(key)
    }
    tileCache[key] = t
    return t
}
let profile = try! RouteBuilder.build(
    points: pipe.waypoints.map { GeoPoint(lat: $0.lat, lon: $0.lon) },
    provider: provider)
check(profile.points.count == pipe.n_points, "точек после ресемплинга: \(profile.points.count)")
check(near(profile.distM, pipe.dist_m, rel: 1e-4), "дистанция \(String(format: "%.1f", profile.distM)) м")
check(near(profile.gainM, pipe.gain_m, rel: 1e-3), "набор \(String(format: "%.1f", profile.gainM)) м")
check(near(profile.lossM, pipe.loss_m, rel: 1e-2), "сброс \(String(format: "%.1f", profile.lossM)) м")
check(near(profile.elevations.first!, pipe.ele_first, rel: 1e-4)
   && near(profile.elevations.last!, pipe.ele_last, rel: 1e-4), "края профиля")

print("GPX:")
let gpxURL = root.appendingPathComponent("Tests/HikeTimeCoreTests/Fixtures/sample.gpx")
let track = GPX.parse(try! Data(contentsOf: gpxURL))!
check(track.points.count == 5, "5 точек")
check(track.elevations?.count == 5, "высоты прочитаны")
check(near(track.elapsedHours ?? 0, 2.5, rel: 1e-9), "полное время 2:30")
// вторая точка стоит на месте 20 минут — движение должно её выбросить
check((track.movingHours() ?? 0) < 2.2, "привал вычтен из времени движения")

print(failed == 0 ? "\nВСЕ ПРОВЕРКИ ПРОЙДЕНЫ" : "\nПРОВАЛЕНО: \(failed)")
exit(failed == 0 ? 0 : 1)
