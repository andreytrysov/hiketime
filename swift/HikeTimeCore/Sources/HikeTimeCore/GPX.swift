import Foundation

/// Разбор GPX: точки трека, высоты и время, если записаны.
public struct GPXTrack: Sendable {
    public let points: [GeoPoint]
    public let elevations: [Double]?     // только если есть у всех точек
    public let times: [Date]?            // только если есть у всех точек

    /// Полное время по меткам, часы.
    public var elapsedHours: Double? {
        guard let t = times, let a = t.first, let b = t.last else { return nil }
        return b.timeIntervalSince(a) / 3600
    }

    /// Время в движении: выбрасываем участки медленнее stopSpeed м/с.
    public func movingHours(stopSpeed: Double = 0.3) -> Double? {
        guard let t = times else { return nil }
        var total = 0.0
        for i in 1..<points.count {
            let dt = t[i].timeIntervalSince(t[i - 1])
            guard dt > 0 else { continue }
            if Geo.haversine(points[i - 1], points[i]) / dt >= stopSpeed {
                total += dt
            }
        }
        return total / 3600
    }
}

public enum GPX {

    public static func parse(_ data: Data) -> GPXTrack? {
        let d = Parser()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse(), !d.points.isEmpty else { return nil }
        return GPXTrack(
            points: d.points,
            elevations: d.eles.count == d.points.count ? d.eles : nil,
            times: d.times.count == d.points.count ? d.times : nil
        )
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var points: [GeoPoint] = []
        var eles: [Double] = []
        var times: [Date] = []
        private var text = ""
        private var inPoint = false
        private let iso = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attrs: [String: String] = [:]) {
            let tag = name.lowercased()
            if tag == "trkpt" || tag == "rtept" {
                inPoint = true
                if let la = Double(attrs["lat"] ?? ""),
                   let lo = Double(attrs["lon"] ?? "") {
                    points.append(GeoPoint(lat: la, lon: lo))
                }
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            let tag = name.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if inPoint && tag == "ele", let v = Double(value) { eles.append(v) }
            if inPoint && tag == "time", let t = iso.date(from: value) { times.append(t) }
            if tag == "trkpt" || tag == "rtept" { inPoint = false }
        }
    }
}
