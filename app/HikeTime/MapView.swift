import SwiftUI
import MapLibre
import HikeTimeCore

/// Карта MapLibre + рисование пальцем.
/// Алгоритмы правок — RouteEditing из ядра, здесь только проекции и жесты.
struct MapView: UIViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero,
                             styleURL: Self.styleURL(base: model.baseLayer))
        context.coordinator.currentBase = model.baseLayer
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
        let wantURL = Self.styleURL(base: model.baseLayer)
        if context.coordinator.currentBase != model.baseLayer
            || context.coordinator.styleGeneration != model.styleGeneration {
            context.coordinator.currentBase = model.baseLayer
            context.coordinator.styleGeneration = model.styleGeneration
            context.coordinator.resetStyle()
            map.styleURL = wantURL
        }
        map.showsUserLocation = model.followUser
        map.userTrackingMode = model.followUser ? .follow : .none
        if context.coordinator.lastFit != model.fitRequest {
            context.coordinator.lastFit = model.fitRequest
            context.coordinator.fitToRoute()
        }
        context.coordinator.syncRoute()
        context.coordinator.syncSpeedColor()
        context.coordinator.syncContours()
        context.coordinator.syncHighlight()
    }

    /// Стиль: отмывка рельефа из вшитых terrarium-тайлов — оффлайн,
    /// без сети и VPN, и легально (AWS Open Data, массовая выгрузка разрешена).
    /// OSM-растр в пакет класть нельзя — их политика запрещает выкачивание.
    /// Адрес источника с учётом отладочного прокси.
    private static func remote(_ source: String, _ path: String) -> String {
        if let p = RegionStore.proxyBase { return "\(p)/\(source)/\(path)" }
        switch source {
        case "otm": return "https://tile.opentopomap.org/\(path)"
        case "osm": return "https://tile.openstreetmap.org/\(path)"
        default:
            return "https://server.arcgisonline.com/ArcGIS/rest/services/"
                 + "World_Imagery/MapServer/tile/\(path)"
        }
    }

    private static func styleURL(base: String) -> URL {
        // тайлы и горизонтали живут в Documents: туда их кладут
        // скачанные районы (вшитый демо-район переносится при первом запуске)
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let res = docs.appendingPathComponent("tiles/terrarium").path
        let contours = docs.appendingPathComponent("contours.geojson").path
        let glyphs = Bundle.main.resourceURL!
            .appendingPathComponent("Tiles/glyphs").path
        // векторные тайлы района, если он скачан: MapLibre читает pbf
        // прямо из файлов, поэтому локальный сервер не нужен
        let vectorDir = docs.appendingPathComponent("tiles/vector")
        let hasVector = FileManager.default.fileExists(atPath: vectorDir.path)
        // слои горизонталей — из вшитого GeoJSON, посчитанного из тех же
        // terrarium-тайлов при сборке пакета (шаг 100 м, жирные каждые 500)
        let contourSource = """
        ,"contours":{"type":"geojson","data":"file://\(contours)"}
        """
        let contourLayers = """
        ,{"id":"contour-minor","type":"line","source":"contours",
          "filter":["==",["get","major"],0],
          "layout":{"visibility":"none"},
          "paint":{"line-color":"#a08050","line-opacity":0.45,"line-width":0.8}},
        {"id":"contour-major","type":"line","source":"contours",
          "filter":["==",["get","major"],1],
          "layout":{"visibility":"none"},
          "paint":{"line-color":"#8a6d3b","line-opacity":0.65,"line-width":1.4}},
        {"id":"contour-label","type":"symbol","source":"contours",
          "filter":["==",["get","major"],1],
          "layout":{"visibility":"none","symbol-placement":"line",
            "text-field":["to-string",["get","ele"]],
            "text-font":["Noto Sans Regular"],"text-size":10,
            "symbol-spacing":320},
          "paint":{"text-color":"#7a5f34",
            "text-halo-color":"#ffffff","text-halo-width":1.2}}
        """
        let json: String
        if base == "vectopo" && hasVector {
            json = Self.vectorTopoStyle(tilesPath: vectorDir.path,
                                        demPath: res,
                                        glyphsPath: glyphs,
                                        contoursPath: contours)
        } else if base == "topo" {
            json = """
            {"version":8,"sources":{"otm":{"type":"raster","tileSize":256,
            "maxzoom":17,"attribution":"© OpenTopoMap (CC-BY-SA), © OpenStreetMap",
            "tiles":["\(remote("otm", "{z}/{x}/{y}.png"))"]}},
            "layers":[{"id":"otm","type":"raster","source":"otm"}]}
            """
        } else if base == "plain" {
            json = """
            {"version":8,"sources":{"osm":{"type":"raster","tileSize":256,
            "maxzoom":19,"attribution":"© OpenStreetMap",
            "tiles":["\(remote("osm", "{z}/{x}/{y}.png"))"]}},
            "layers":[{"id":"osm","type":"raster","source":"osm"}]}
            """
        } else if base == "satellite" {
            json = """
            {"version":8,"glyphs":"file://\(glyphs)/{fontstack}/{range}.pbf","sources":{"sat":{"type":"raster","tileSize":256,
            "maxzoom":18,"attribution":"Esri",
            "tiles":["\(remote("sat", "{z}/{y}/{x}"))"]}\(contourSource)},
            "layers":[{"id":"sat","type":"raster","source":"sat"}\(contourLayers)]}
            """
        } else {
            json = """
            {"version":8,"glyphs":"file://\(glyphs)/{fontstack}/{range}.pbf","sources":{"dem":{"type":"raster-dem","encoding":"terrarium",
            "tileSize":256,"maxzoom":12,
            "attribution":"Elevation: Mapzen terrarium (AWS Open Data)",
            "tiles":["file://\(res)/{z}/{x}/{y}.png"]}\(contourSource)},
            "layers":[
              {"id":"bg","type":"background","paint":{"background-color":"#eef1ec"}},
              {"id":"hills","type":"hillshade","source":"dem",
               "paint":{"hillshade-exaggeration":0.6,
                        "hillshade-shadow-color":"#5a5a4d",
                        "hillshade-highlight-color":"#ffffff"}}\(contourLayers)]}
            """
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-\(base).json")
        try? json.data(using: .utf8)!.write(to: url)
        return url
    }

    /// Стиль оффлайн-топо: рельеф отмывкой снизу, поверх — векторные
    /// слои OSM (вода, лес, тропы, дороги) и подписи.
    private static func vectorTopoStyle(tilesPath: String, demPath: String,
                                        glyphsPath: String,
                                        contoursPath: String) -> String {
        """
        {"version":8,
         "glyphs":"file://\(glyphsPath)/{fontstack}/{range}.pbf",
         "sources":{
           "dem":{"type":"raster-dem","encoding":"terrarium","tileSize":256,
                  "maxzoom":12,"attribution":"Elevation: Mapzen terrarium (AWS Open Data)",
                  "tiles":["file://\(demPath)/{z}/{x}/{y}.png"]},
           "osm":{"type":"vector","maxzoom":14,
                  "attribution":"© OpenMapTiles © OpenStreetMap",
                  "tiles":["file://\(tilesPath)/{z}/{x}/{y}.pbf"]},
           "contours":{"type":"geojson","data":"file://\(contoursPath)"}},
         "layers":[
          {"id":"bg","type":"background","paint":{"background-color":"#f6f4ef"}},
          {"id":"hills","type":"hillshade","source":"dem",
           "paint":{"hillshade-exaggeration":0.45,
                    "hillshade-shadow-color":"#6b6a5c",
                    "hillshade-highlight-color":"#ffffff"}},
          {"id":"landcover","type":"fill","source":"osm","source-layer":"landcover",
           "paint":{"fill-color":"#d7e3cd","fill-opacity":0.45}},
          {"id":"water","type":"fill","source":"osm","source-layer":"water",
           "paint":{"fill-color":"#a8cfe0"}},
          {"id":"waterway","type":"line","source":"osm","source-layer":"waterway",
           "paint":{"line-color":"#7fb4cc","line-width":["interpolate",["linear"],["zoom"],10,0.6,15,2]}},
          {"id":"contour-minor","type":"line","source":"contours",
           "filter":["==",["get","major"],0],
           "paint":{"line-color":"#a08050","line-opacity":0.4,"line-width":0.7}},
          {"id":"contour-major","type":"line","source":"contours",
           "filter":["==",["get","major"],1],
           "paint":{"line-color":"#8a6d3b","line-opacity":0.6,"line-width":1.3}},
          {"id":"contour-label","type":"symbol","source":"contours",
           "filter":["==",["get","major"],1],
           "layout":{"symbol-placement":"line","text-field":["to-string",["get","ele"]],
                     "text-font":["Noto Sans Regular"],"text-size":10,"symbol-spacing":320},
           "paint":{"text-color":"#7a5f34","text-halo-color":"#ffffff","text-halo-width":1.2}},
          {"id":"aerialway","type":"line","source":"osm","source-layer":"transportation",
           "filter":["in",["get","class"],["literal",["aerialway","rail","ferry"]]],
           "paint":{"line-color":"#9a9a94","line-width":0.9,"line-dasharray":[4,3]}},
          {"id":"road","type":"line","source":"osm","source-layer":"transportation",
           "filter":["!",["in",["get","class"],["literal",["path","track","aerialway","rail","ferry"]]]],
           "paint":{"line-color":"#ffffff","line-width":["interpolate",["linear"],["zoom"],11,0.8,16,3.4],
                    "line-opacity":0.9}},
          {"id":"path","type":"line","source":"osm","source-layer":"transportation",
           "filter":["in",["get","class"],["literal",["path","track"]]],
           "paint":{"line-color":"#b5651d","line-width":["interpolate",["linear"],["zoom"],12,0.8,16,2],
                    "line-dasharray":[2,1.5]}},
          {"id":"place","type":"symbol","source":"osm","source-layer":"place",
           "layout":{"text-field":["coalesce",["get","name:ru"],["get","name"]],
                     "text-font":["Noto Sans Regular"],
                     "text-size":["interpolate",["linear"],["zoom"],10,10,14,14]},
           "paint":{"text-color":"#3c3a33","text-halo-color":"#ffffff","text-halo-width":1.4}}]}
        """
    }

    // MARK: координатор

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        let model: AppModel
        weak var map: MLNMapView?
        var drawGesture: UIPanGestureRecognizer?
        private var routeSource: MLNShapeSource?
        private var curSource: MLNShapeSource?
        private var speedSource: MLNShapeSource?
        private var previewSource: MLNShapeSource?
        var lastFit = 0
        var currentBase = ""
        var styleGeneration = -1

        func resetStyle() {
            styleReady = false
            routeSource = nil
            curSource = nil
            speedSource = nil
            previewSource = nil
        }
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

            let spd = MLNShapeSource(identifier: "spd", shape: nil, options: nil)
            style.addSource(spd)
            speedSource = spd
            let spdLine = MLNLineStyleLayer(identifier: "route-spd", source: spd)
            spdLine.lineWidth = NSExpression(forConstantValue: 5)
            spdLine.lineCap = NSExpression(forConstantValue: "round")
            spdLine.lineJoin = NSExpression(forConstantValue: "round")
            spdLine.lineColor = NSExpression(
                format: "MLN_MATCH(zone, 0, %@, 1, %@, 2, %@, %@)",
                UIColor(red: 0.64, green: 0.23, blue: 0.16, alpha: 1),
                UIColor(red: 0.85, green: 0.63, blue: 0.36, alpha: 1),
                UIColor(red: 0.79, green: 0.75, blue: 0.48, alpha: 1),
                UIColor(red: 0.16, green: 0.42, blue: 0.30, alpha: 1))
            style.addLayer(spdLine)

            let prev = MLNShapeSource(identifier: "preview", shape: nil,
                                      options: nil)
            style.addSource(prev)
            previewSource = prev
            let prevLine = MLNLineStyleLayer(identifier: "preview-line",
                                             source: prev)
            prevLine.lineWidth = NSExpression(
                format: "MLN_MATCH(erase, 1, 14, 4)")
            prevLine.lineOpacity = NSExpression(
                format: "MLN_MATCH(erase, 1, 0.5, 0.9)")
            prevLine.lineColor = NSExpression(
                format: "MLN_MATCH(erase, 1, %@, %@)",
                UIColor(red: 0.72, green: 0.25, blue: 0.20, alpha: 1),
                UIColor(red: 0.16, green: 0.42, blue: 0.30, alpha: 1))
            prevLine.lineCap = NSExpression(forConstantValue: "round")
            prevLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(prevLine)

            let cur = MLNShapeSource(identifier: "cur", shape: nil, options: nil)
            style.addSource(cur)
            curSource = cur
            let dot = MLNCircleStyleLayer(identifier: "cur-pt", source: cur)
            dot.circleRadius = NSExpression(forConstantValue: 6)
            dot.circleColor = NSExpression(forConstantValue: UIColor.black)
            dot.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            dot.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(dot)

            styleReady = true
            syncRoute()
            syncSpeedColor()
            syncContours()
            syncHighlight()
        }

        /// Цвет по скорости: сегменты с зоной 0..3 (медленно -> быстро).
        func syncSpeedColor() {
            guard styleReady, let spd = speedSource, let map else { return }
            let show = model.speedColor
            if let layer = map.style?.layer(withIdentifier: "route-spd") {
                layer.isVisible = show
            }
            for id in ["route-line", "route-halo"] {
                map.style?.layer(withIdentifier: id)?.isVisible = !show
            }
            guard show, let prof = model.profile,
                  prof.points.count == prof.segments.count + 1 else {
                if !show { spd.shape = nil }
                return
            }
            let m = EnergyModel(bodyKg: model.bodyKg, loadKg: model.loadKg,
                                powerPerKg: model.power,
                                terrain: model.terrain)
            var feats: [MLNPolylineFeature] = []
            for (i, seg) in prof.segments.enumerated() where seg.distance > 0 {
                let v = m.speed(slope: seg.dh / seg.distance)
                let zone = v < 0.5 ? 0 : v < 0.9 ? 1 : v < 1.25 ? 2 : 3
                var coords = [
                    CLLocationCoordinate2D(latitude: prof.points[i].lat,
                                           longitude: prof.points[i].lon),
                    CLLocationCoordinate2D(latitude: prof.points[i + 1].lat,
                                           longitude: prof.points[i + 1].lon),
                ]
                let f = MLNPolylineFeature(coordinates: &coords, count: 2)
                f.attributes = ["zone": zone]
                feats.append(f)
            }
            spd.shape = MLNShapeCollectionFeature(shapes: feats)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated: Bool) {
            let b = mapView.visibleCoordinateBounds
            model.visibleBounds = (b.sw.latitude, b.sw.longitude,
                                   b.ne.latitude, b.ne.longitude)
        }

        func fitToRoute() {
            guard let map else { return }
            var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
            if let b = model.fitBounds {
                (minLat, minLon, maxLat, maxLon) = (b.minLat, b.minLon, b.maxLat, b.maxLon)
                model.fitBounds = nil
            } else {
                guard model.path.count >= 2 else { return }
                for p in model.path {
                    minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
                    minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
                }
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
            map.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 120, left: 50,
                                          bottom: 280, right: 50),
                animated: true, completionHandler: nil)
        }

        func syncContours() {
            guard styleReady, let map else { return }
            for id in ["contour-minor", "contour-major", "contour-label"] {
                map.style?.layer(withIdentifier: id)?.isVisible = model.contours
            }
        }

        func syncHighlight() {
            guard styleReady, let cur = curSource else { return }
            guard let i = model.highlightIndex,
                  let prof = model.profile,
                  i < prof.points.count else {
                cur.shape = nil
                return
            }
            let p = prof.points[i]
            cur.shape = MLNPointFeature()
            (cur.shape as? MLNPointFeature)?.coordinate =
                CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
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
                    updatePreview()
                }
            case .ended, .cancelled:
                finishStroke()
            default:
                break
            }
        }

        private func updatePreview() {
            guard let map, let prev = previewSource, stroke.count > 1 else { return }
            var coords = stroke.map {
                map.convert($0, toCoordinateFrom: map)
            }
            let f = MLNPolylineFeature(coordinates: &coords,
                                       count: UInt(coords.count))
            f.attributes = ["erase": model.eraseMode ? 1 : 0]
            prev.shape = f
        }

        private func finishStroke() {
            guard let map, stroke.count >= 2 else { stroke = []; return }
            typealias P = RouteEditing.P
            let strokePx = RouteEditing.simplify(
                stroke.map { P(Double($0.x), Double($0.y)) }, tolerance: 2.5)
            stroke = []
            previewSource?.shape = nil

            // маршрут -> экран, правка, экран -> маршрут
            var pathPx = model.path.map { gp -> P in
                let c = map.convert(
                    CLLocationCoordinate2D(latitude: gp.lat, longitude: gp.lon),
                    toPointTo: map)
                return P(Double(c.x), Double(c.y))
            }

            if model.eraseMode {
                let e = RouteEditing.eraseCut(strokePx, path: &pathPx)
                if e == .missed {
                    model.toast("Коснитесь линии — всё после этого места сотрётся")
                    return
                }
            } else {
                let outcome = RouteEditing.applyStroke(strokePx, to: &pathPx)
                if outcome == .rejected {
                    model.toast("Линия далеко от маршрута — начните у его конца")
                    return
                }
                if outcome == .replacedSegment {
                    model.toast("Участок заменён новой линией")
                }
            }

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
