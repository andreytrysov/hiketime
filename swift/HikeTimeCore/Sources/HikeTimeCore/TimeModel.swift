import Foundation

/// Модель времени прохождения. Перенос прототипа один в один:
/// полином Minetti (стоимость метра пути по уклону) + бюджет мощности.
/// Эталонные значения зашиты в тесты и сверены с Python и JS.
public enum TimeModel {

    public static let maxSpeed = 6.0 / 3.6   // м/с — быстрее пешком не ходят
    public static let minSpeed = 0.15        // м/с — ниже уже не ходьба

    /// Стоимость метра пути, Дж/(кг·м), по уклону i = dh/dx.
    /// Minetti et al. 2002; минимум около i = -0.10 — пологий спуск
    /// дешевле ровного. За |i| > 0.45 полином расходится, зажимаем.
    public static func minettiCost(_ slope: Double) -> Double {
        let i = max(-0.45, min(0.45, slope))
        let c = 280.5 * pow(i, 5) - 58.7 * pow(i, 4) - 76.8 * pow(i, 3)
              + 51.9 * pow(i, 2) + 19.6 * i + 2.5
        return max(c, 0.4)
    }
}

/// Сегмент маршрута: длина по горизонтали и перепад, метры.
public struct Segment: Sendable, Codable {
    public let distance: Double
    public let dh: Double
    public init(distance: Double, dh: Double) {
        self.distance = distance
        self.dh = dh
    }
}

/// Энергетическая модель: скорость из посильной мощности.
public struct EnergyModel: Sendable {
    /// Масса тела, кг.
    public var bodyKg: Double
    /// Груз, кг.
    public var loadKg: Double
    /// Ватт на кг массы тела, которые человек держит часами (форма).
    public var powerPerKg: Double
    /// Во сколько раз кг груза дороже кг своего тела.
    public var loadFactor: Double
    /// Множитель стоимости покрытия: тропа 1.0, тундра/кусты 1.55, болото/камни 1.9.
    public var terrain: Double
    /// Нелинейная надбавка за тяжёлый рюкзак (стиль Пандольфа), 0 до калибровки.
    public var loadPenaltyK: Double

    public init(bodyKg: Double = 75, loadKg: Double = 0,
                powerPerKg: Double = 3.6, loadFactor: Double = 1.15,
                terrain: Double = 1.0, loadPenaltyK: Double = 0) {
        self.bodyKg = bodyKg
        self.loadKg = loadKg
        self.powerPerKg = powerPerKg
        self.loadFactor = loadFactor
        self.terrain = terrain
        self.loadPenaltyK = loadPenaltyK
    }

    var effectiveKg: Double { bodyKg + loadKg * loadFactor }
    var powerW: Double { powerPerKg * bodyKg }   // мощность даёт тело

    public func speed(slope: Double) -> Double {
        let rel = loadKg / bodyKg
        let cost = TimeModel.minettiCost(slope) * terrain
                 * (1.0 + loadPenaltyK * rel * rel)
        let v = powerW / (cost * effectiveKg)
        return max(TimeModel.minSpeed, min(TimeModel.maxSpeed, v))
    }

    /// Ходовое время в часах, без привалов.
    public func timeHours(_ segments: [Segment]) -> Double {
        var t = 0.0
        for s in segments where s.distance > 0 {
            t += s.distance / speed(slope: s.dh / s.distance)
        }
        return t / 3600
    }
}

/// Привалы: походный ритм ~50/10 плюс обед на длинных маршрутах.
public struct Breaks: Sendable, Equatable {
    public let totalHours: Double
    public let shortBreaks: Int      // по 10 минут
    public let lunchMinutes: Int

    public init(movingHours: Double) {
        let movMin = movingHours * 60
        let n10 = max(0, Int((movMin / 55).rounded(.up)) - 1)
        let lunch = movMin > 240 ? 30 : 0
        self.shortBreaks = n10
        self.lunchMinutes = lunch
        self.totalHours = movingHours + Double(n10 * 10 + lunch) / 60
    }
}

/// Классические правила — для сравнения и онбординга.
public enum ClassicModels {

    public static func naive(distM: Double, kmh: Double = 4) -> Double {
        distM / 1000 / kmh
    }

    public static func naismithLangmuir(distM: Double, gainM: Double,
                                        lossM: Double, segments: [Segment]) -> Double {
        var h = distM / 1000 / 5 + gainM / 600
        for s in segments where s.dh < 0 && s.distance > 0 {
            let angle = atan(abs(s.dh) / s.distance) * 180 / .pi
            if angle >= 5 && angle <= 12 {
                h -= abs(s.dh) / 300 * (10.0 / 60)
            } else if angle > 12 {
                h += abs(s.dh) / 300 * (10.0 / 60)
            }
        }
        return max(h, 0)
    }

    public static func din33466(distM: Double, gainM: Double, lossM: Double) -> Double {
        let horiz = distM / 1000 / 4
        let vert = gainM / 300 + lossM / 500
        return max(horiz, vert) + min(horiz, vert) / 2
    }

    public static func munter(distM: Double, gainM: Double, lossM: Double,
                              up: Double = 4, flat: Double = 6, down: Double = 10) -> Double {
        let km = distM / 1000
        let total = max(gainM + lossM, 1e-9)
        var t = 0.0
        if gainM > 0 { t += (km * gainM / total + gainM / 100) / up }
        if lossM > 0 { t += (km * lossM / total + lossM / 100) / down }
        if gainM + lossM == 0 { t = km / flat }
        return t
    }

    public static func tobler(_ segments: [Segment]) -> Double {
        var t = 0.0
        for s in segments where s.distance > 0 {
            let slope = s.dh / s.distance
            let kmh = 6 * exp(-3.5 * abs(slope + 0.05))
            t += (s.distance / 1000) / max(kmh, 0.3)
        }
        return t
    }
}
