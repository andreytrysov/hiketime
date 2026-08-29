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

print("редактирование маршрута (сценарии, выверенные на веб-прототипе):")
typealias P = RouteEditing.P
var path: [P] = []
check(RouteEditing.applyStroke([P(400,300),P(400,700),P(400,1300)], to: &path) == .started
      && path.count == 3, "первый мазок начинает маршрут")
check(RouteEditing.applyStroke([P(900,1400),P(950,1450)], to: &path) == .rejected
      && path.count == 3, "далёкий мазок отклонён")
check(RouteEditing.applyStroke([P(400,500),P(550,700),P(400,900)], to: &path) == .replacedSegment,
      "перечёркивание заменяет участок")
let before = path.count
check(RouteEditing.applyStroke([P(400,1300),P(460,1380)], to: &path) == .extended
      && path.count == before + 2, "продление с хвоста")
check(RouteEditing.applyStroke([P(400,300),P(340,240)], to: &path) == .extended
      && path[0] == P(340,240), "продление с головы (мазок развёрнут)")

var knife: [P] = [P(0,0),P(100,0),P(200,0),P(300,0),P(400,0)]
check(RouteEditing.eraseCut([P(250,10)], path: &knife) == .trimmed
      && knife.count == 4 && knife[3] == P(250,0), "нож: рез в середине, хвост стёрт")
check(RouteEditing.eraseCut([P(500,300)], path: &knife) == .missed, "нож мимо линии")
check(RouteEditing.eraseCut([P(0,5)], path: &knife) == .cleared && knife.isEmpty,
      "нож у начала стирает всё")

let zig: [P] = [P(0,0),P(3,1),P(6,0),P(10,2),P(50,0),P(100,0)]
let simp = RouteEditing.simplify(zig, tolerance: 5)
check(simp.first == zig.first && simp.last == zig.last && simp.count < zig.count,
      "упрощение держит концы и убирает шум")

print("горизонтали (marching squares):")
// конус: высота = 1000 - расстояние от центра; линии должны быть замкнутыми кольцами
var cone = [Double]()
let N = 60
for y in 0..<N {
    for x in 0..<N {
        let dx = Double(x - N/2), dy = Double(y - N/2)
        cone.append(1000 - (dx*dx + dy*dy).squareRoot() * 20)
    }
}
let lines = Contours.build(grid: .init(values: cone, width: N, height: N),
                           step: 100, majorEvery: 500)
check(!lines.isEmpty, "линии построены: \(lines.count)")
check(lines.allSatisfy { $0.points.count >= 3 }, "все линии содержательны")
check(lines.contains { $0.major }, "есть жирные (кратные 500)")
// сравниваем кольца, целиком лежащие внутри сетки: у конуса
// нижние горизонтали обрезаны краем и потому короткие
let byEle = Dictionary(grouping: lines.filter { $0.elevation >= 600 },
                       by: { $0.elevation })
    .mapValues { ls -> Double in
        var total = 0.0
        for l in ls {
            for i in 1..<l.points.count {
                let dx = l.points[i].0 - l.points[i-1].0
                let dy = l.points[i].1 - l.points[i-1].1
                total += (dx*dx + dy*dy).squareRoot()
            }
        }
        return total
    }
let sorted = byEle.sorted { $0.key < $1.key }
if sorted.count >= 2 {
    check(sorted.first!.value > sorted.last!.value,
          "кольца сужаются к вершине: \(Int(sorted.first!.value)) -> \(Int(sorted.last!.value))")
    check(sorted.count >= 3, "внутренних уровней: \(sorted.count)")
}

print("тайловая арифметика (пакеты районов):")
// те же формулы, что в RegionStore — сверяем с Python-эталоном проекта
func tileIndex(lat: Double, lon: Double, z: Int) -> (Int, Int) {
    let n = pow(2.0, Double(z))
    let x = Int((lon + 180) / 360 * n)
    let latRad = lat * .pi / 180
    let y = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n)
    return (x, y)
}
// Шварцзее (45.9824, 7.7025) на z12 должен попасть в тайл 2135/1457 —
// именно его мы выгружали для фикстур
let t = tileIndex(lat: 45.9824, lon: 7.7025, z: 12)
check(t.0 == 2135 && t.1 == 1457, "тайл Шварцзее z12: \(t.0)/\(t.1)")

// прямоугольник района: сколько тайлов покрывает 0.1° около Церматта
let cornerNW = tileIndex(lat: 46.05, lon: 7.65, z: 12)
let cornerSE = tileIndex(lat: 45.95, lon: 7.75, z: 12)
let cols = abs(cornerSE.0 - cornerNW.0) + 1
let rows = abs(cornerSE.1 - cornerNW.1) + 1
check(cols * rows >= 4 && cols * rows <= 20,
      "0.1° около Церматта = \(cols)x\(rows) тайлов")

print(failed == 0 ? "\nВСЕ ПРОВЕРКИ ПРОЙДЕНЫ" : "\nПРОВАЛЕНО: \(failed)")
exit(failed == 0 ? 0 : 1)
