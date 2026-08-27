import Foundation

/// Точка (широта, долгота) в градусах.
public struct GeoPoint: Sendable, Codable, Equatable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public enum Geo {

    static let earthR = 6_371_008.8

    public static func haversine(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let la1 = a.lat * .pi / 180, la2 = b.lat * .pi / 180
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthR * asin(sqrt(h))
    }

    /// Точки через равные интервалы вдоль ломаной: набор высоты не должен
    /// зависеть от того, как густо записан исходный трек.
    public static func resample(_ points: [GeoPoint], step: Double = 25) -> [GeoPoint] {
        guard points.count >= 2 else { return points }
        var out = [points[0]]
        var acc = 0.0
        for i in 1..<points.count {
            var a = points[i - 1]
            let b = points[i]
            var d = haversine(a, b)
            while acc + d >= step {
                let t = (step - acc) / d
                a = GeoPoint(lat: a.lat + (b.lat - a.lat) * t,
                             lon: a.lon + (b.lon - a.lon) * t)
                out.append(a)
                d = haversine(a, b)
                acc = 0
            }
            acc += d
        }
        out.append(points[points.count - 1])
        return out
    }

    /// Скользящее среднее: глушит шум DEM и GPS, иначе набор раздувается.
    public static func smooth(_ values: [Double], window: Int = 5) -> [Double] {
        guard window >= 2, values.count >= window else { return values }
        let half = window / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count, i + half + 1)
            return values[lo..<hi].reduce(0, +) / Double(hi - lo)
        }
    }

    /// Набор и сброс с порогом: изменения мельче порога — шум.
    public static func gainLoss(_ elevations: [Double], threshold: Double = 2)
        -> (gain: Double, loss: Double) {
        guard var ref = elevations.first else { return (0, 0) }
        var gain = 0.0, loss = 0.0
        for e in elevations.dropFirst() {
            let d = e - ref
            if d > threshold { gain += d; ref = e }
            else if d < -threshold { loss -= d; ref = e }
        }
        return (gain, loss)
    }

    /// Профиль высот -> сегменты для модели времени.
    public static func segments(points: [GeoPoint], elevations: [Double]) -> [Segment] {
        precondition(points.count == elevations.count)
        var out: [Segment] = []
        out.reserveCapacity(max(points.count - 1, 0))
        for i in 1..<max(points.count, 1) {
            out.append(Segment(distance: haversine(points[i - 1], points[i]),
                               dh: elevations[i] - elevations[i - 1]))
        }
        return out
    }
}
