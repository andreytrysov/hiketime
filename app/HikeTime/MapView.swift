import SwiftUI
import MapLibre
import HikeTimeCore

/// Карта MapLibre + рисование пальцем.
/// Алгоритмы правок — RouteEditing из ядра, здесь только проекции и жесты.
struct MapView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL())
        map.setCenter(CLLocationCoordinate2D(latitude: 45.974, longitude: 7.69),
                      zoomLevel: 12.2, animated: false)
        map.delegate = context.coordinator
        map.showsUserLocation = false
        context.coordinator.map = map

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleDraw(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)
        context.coordinator.drawGesture = pan
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        // в режиме рисования карта не таскается одним пальцем
        map.allowsScrolling = !model.drawMode
        context.coordinator.syncRoute()
    }

    /// Стиль: онлайн-топо для первой сборки. Оффлайн-пакеты — следующий шаг.
    private static func styleURL() -> URL {
        let json = """
        {"version":8,"sources":{"topo":{"type":"raster","tileSize":256,"maxzoom":17,
        "attribution":"© OpenStreetMap",
        "tiles":["https://tile.openstreetmap.org/{z}/{x}/{y}.png"]}},
        "layers":[{"id":"topo","type":"raster","source":"topo"}]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("style.json")
        try? json.data(using: .utf8)!.write(to: url)
        return url
    }

    // MARK: координатор

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        let model: AppModel
        weak var map: MLNMapView?
        var drawGesture: UIPanGestureRecognizer?
        private var routeSource: MLNShapeSource?
        private var stroke: [CGPoint] = []
        private var styleReady = false

        init(model: AppModel) { self.model = model }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let source = MLNShapeSource(identifier: "route",
                                        shape: nil, options: nil)
            style.addSource(source)
            routeSource = source

            let halo = MLNLineStyleLayer(identifier: "route-halo", source: source)
            halo.lineColor = NSExpression(forConstantValue: UIColor.white)
            halo.lineWidth = NSExpression(forConstantValue: 7)
            halo.lineCap = NSExpression(forConstantValue: "round")
            halo.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(halo)

            let line = MLNLineStyleLayer(identifier: "route-line", source: source)
            line.lineColor = NSExpression(forConstantValue:
                UIColor(red: 0.18, green: 0.44, blue: 0.31, alpha: 1))
            line.lineWidth = NSExpression(forConstantValue: 4)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(line)

            styleReady = true
            syncRoute()
        }

        func syncRoute() {
            guard styleReady, let source = routeSource else { return }
            let pts = model.path
            guard pts.count >= 2 else {
                source.shape = nil
                return
            }
            var coords = pts.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            source.shape = MLNPolylineFeature(coordinates: &coords,
                                              count: UInt(coords.count))
        }

        // жест активен только в режиме рисования
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            model.drawMode
        }

        @objc func handleDraw(_ g: UIPanGestureRecognizer) {
            guard model.drawMode, let map else { return }
            let p = g.location(in: map)
            switch g.state {
            case .began:
                stroke = [p]
            case .changed:
                if let last = stroke.last,
                   pow(p.x - last.x, 2) + pow(p.y - last.y, 2) > 4 {
                    stroke.append(p)
                }
            case .ended, .cancelled:
                finishStroke()
            default:
                break
            }
        }

        private func finishStroke() {
            guard let map, stroke.count >= 2 else { stroke = []; return }
            typealias P = RouteEditing.P
            let strokePx = RouteEditing.simplify(
                stroke.map { P(Double($0.x), Double($0.y)) }, tolerance: 2.5)
            stroke = []

            // маршрут -> экран, правка, экран -> маршрут
            var pathPx = model.path.map { gp -> P in
                let c = map.convert(
                    CLLocationCoordinate2D(latitude: gp.lat, longitude: gp.lon),
                    toPointTo: map)
                return P(Double(c.x), Double(c.y))
            }

            let outcome: RouteEditing.StrokeOutcome
            if model.eraseMode {
                let e = RouteEditing.eraseCut(strokePx, path: &pathPx)
                outcome = e == .missed ? .rejected : .extended
                if e == .missed { return }
            } else {
                outcome = RouteEditing.applyStroke(strokePx, to: &pathPx)
                if outcome == .rejected { return }
            }
            _ = outcome

            model.pushHistory()
            model.path = pathPx.map { px in
                let c = map.convert(CGPoint(x: px.x, y: px.y),
                                    toCoordinateFrom: map)
                return GeoPoint(lat: c.latitude, lon: c.longitude)
            }
            syncRoute()
            model.recomputeProfile()
        }
    }
}
