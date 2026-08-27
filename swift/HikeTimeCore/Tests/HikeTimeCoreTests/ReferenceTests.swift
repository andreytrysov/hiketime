import XCTest
@testable import HikeTimeCore

/// Сверка с эталоном: фикстура сгенерирована Python-прототипом
/// (реальный профиль Шварцзее -> Хёрнлихютте, 112 сегментов).
/// Если эти тесты зелёные — Swift-модель считает то же, что прототип.
final class ReferenceTests: XCTestCase {

    struct Fixture: Codable {
        struct EnergyCase: Codable {
            let body: Double
            let load: Double
            let power: Double
            let hours: Double
        }
        struct Classic: Codable {
            let naismith: Double
            let din: Double
            let munter: Double
            let tobler: Double
        }
        let segments: [[Double]]
        let dist_m: Double
        let gain_m: Double
        let loss_m: Double
        let energy: [EnergyCase]
        let classic: Classic
        let minetti: [[Double]]
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "Fixtures/reference",
                                    withExtension: "json")!
        return try! JSONDecoder().decode(Fixture.self,
                                         from: Data(contentsOf: url))
    }()

    var segs: [Segment] {
        Self.fixture.segments.map { Segment(distance: $0[0], dh: $0[1]) }
    }

    func testMinettiCurveMatchesPython() {
        for pair in Self.fixture.minetti {
            XCTAssertEqual(TimeModel.minettiCost(pair[0]), pair[1],
                           accuracy: 1e-5,
                           "уклон \(pair[0])")
        }
    }

    func testMinettiMinimumOnGentleDescent() {
        // физиология: пологий спуск дешевле ровного
        XCTAssertLessThan(TimeModel.minettiCost(-0.10), TimeModel.minettiCost(0))
        XCTAssertGreaterThan(TimeModel.minettiCost(-0.30), TimeModel.minettiCost(-0.10))
    }

    func testEnergyModelMatchesPythonAcross27Cases() {
        for c in Self.fixture.energy {
            let m = EnergyModel(bodyKg: c.body, loadKg: c.load, powerPerKg: c.power)
            XCTAssertEqual(m.timeHours(segs), c.hours,
                           accuracy: c.hours * 0.001,
                           "body \(c.body) load \(c.load) power \(c.power)")
        }
    }

    func testClassicModelsMatchPython() {
        let f = Self.fixture
        XCTAssertEqual(ClassicModels.naismithLangmuir(distM: f.dist_m, gainM: f.gain_m,
                                                      lossM: f.loss_m, segments: segs),
                       f.classic.naismith, accuracy: 1e-4)
        XCTAssertEqual(ClassicModels.din33466(distM: f.dist_m, gainM: f.gain_m,
                                              lossM: f.loss_m),
                       f.classic.din, accuracy: 1e-4)
        XCTAssertEqual(ClassicModels.munter(distM: f.dist_m, gainM: f.gain_m,
                                            lossM: f.loss_m),
                       f.classic.munter, accuracy: 1e-4)
        XCTAssertEqual(ClassicModels.tobler(segs), f.classic.tobler, accuracy: 1e-4)
    }

    func testMoreLoadIsSlower() {
        let light = EnergyModel(loadKg: 5).timeHours(segs)
        let heavy = EnergyModel(loadKg: 25).timeHours(segs)
        XCTAssertGreaterThan(heavy, light)
    }

    func testHeavierBodyCarriesSameLoadFaster() {
        let small = EnergyModel(bodyKg: 55, loadKg: 20).timeHours(segs)
        let big = EnergyModel(bodyKg: 95, loadKg: 20).timeHours(segs)
        XCTAssertLessThan(big, small)
    }

    func testBreaksRhythm() {
        let short = Breaks(movingHours: 0.8)
        XCTAssertEqual(short.shortBreaks, 0)
        XCTAssertEqual(short.lunchMinutes, 0)

        let medium = Breaks(movingHours: 3.2)   // 192 мин -> 3 привала
        XCTAssertEqual(medium.shortBreaks, 3)
        XCTAssertEqual(medium.lunchMinutes, 0)

        let long = Breaks(movingHours: 5.0)     // 300 мин -> 5 привалов + обед
        XCTAssertEqual(long.shortBreaks, 5)
        XCTAssertEqual(long.lunchMinutes, 30)
        XCTAssertEqual(long.totalHours, 5 + 50.0/60 + 0.5, accuracy: 1e-9)
    }

    func testResampleKeepsLength() {
        let pts = [GeoPoint(lat: 45.98, lon: 7.70), GeoPoint(lat: 45.96, lon: 7.68)]
        let dense = Geo.resample(pts, step: 25)
        let orig = Geo.haversine(pts[0], pts[1])
        var sum = 0.0
        for i in 1..<dense.count { sum += Geo.haversine(dense[i-1], dense[i]) }
        XCTAssertEqual(sum, orig, accuracy: orig * 1e-6)
        XCTAssertGreaterThan(dense.count, 50)
    }
}
