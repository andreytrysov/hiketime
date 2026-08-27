import Foundation

/// Конвейер: точки маршрута -> профиль -> сегменты -> сводка.
/// Повторяет route.py прототипа.
public struct RouteProfile: Sendable {
    public let points: [GeoPoint]        // после ресемплинга
    public let elevations: [Double]      // сглаженные
    public let segments: [Segment]
    public let distM: Double
    public let gainM: Double
    public let lossM: Double
}

public enum RouteBuilder {

    public static func build(points: [GeoPoint],
                             zoom: Int = 12,
                             step: Double = 25,
                             smoothWindow: Int = 5,
                             threshold: Double = 2,
                             provider: DEM.TileProvider) throws -> RouteProfile {
        let dense = Geo.resample(points, step: step)
        let raw = try dense.map {
            try DEM.elevation(lat: $0.lat, lon: $0.lon, zoom: zoom, provider: provider)
        }
        let ele = Geo.smooth(raw, window: smoothWindow)
        let segs = Geo.segments(points: dense, elevations: ele)
        let (gain, loss) = Geo.gainLoss(ele, threshold: threshold)
        return RouteProfile(points: dense, elevations: ele, segments: segs,
                            distM: segs.reduce(0) { $0 + $1.distance },
                            gainM: gain, lossM: loss)
    }
}
