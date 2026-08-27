import Foundation

/// Редактирование маршрута рисованием. Планарные координаты (экранные
/// пиксели): проекцию делает карта, логика от неё не зависит.
/// Поведение выверено на веб-прототипе:
///  - первый мазок начинает маршрут;
///  - мазок, оба конца которого легли на линию, заменяет участок
///    («правка перечёркиванием», механика Footpath);
///  - иначе мазок продлевает ближайший конец;
///  - далёкий мазок отклоняется, а не приклеивается молча;
///  - ластик-нож: первое по ходу маршрута касание — новый конец.
public enum RouteEditing {

    public typealias P = SIMD2<Double>

    // MARK: упрощение (Дуглас–Пекер)

    public static func simplify(_ pts: [P], tolerance: Double) -> [P] {
        guard pts.count >= 3 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true

        func d2(_ p: P, _ a: P, _ b: P) -> Double {
            var x = a.x, y = a.y
            let dx = b.x - a.x, dy = b.y - a.y
            if dx != 0 || dy != 0 {
                let t = ((p.x - x) * dx + (p.y - y) * dy) / (dx * dx + dy * dy)
                if t > 1 { x = b.x; y = b.y }
                else if t > 0 { x += dx * t; y += dy * t }
            }
            let ex = p.x - x, ey = p.y - y
            return ex * ex + ey * ey
        }

        func rec(_ i: Int, _ j: Int) {
            var maxD = 0.0
            var idx = -1
            for k in (i + 1)..<j {
                let d = d2(pts[k], pts[i], pts[j])
                if d > maxD { maxD = d; idx = k }
            }
            if maxD > tolerance * tolerance {
                keep[idx] = true
                rec(i, idx)
                rec(idx, j)
            }
        }
        rec(0, pts.count - 1)
        return pts.indices.compactMap { keep[$0] ? pts[$0] : nil }
    }

    // MARK: привязка к ломаной

    struct Projection {
        let segment: Int      // индекс начала отрезка
        let t: Double         // доля вдоль отрезка
        let distance: Double
        var order: Double { Double(segment) + t }
    }

    static func project(_ p: P, onto a: P, _ b: P) -> (t: Double, d: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
        t = max(0, min(1, t))
        let ex = p.x - (a.x + dx * t), ey = p.y - (a.y + dy * t)
        return (t, (ex * ex + ey * ey).squareRoot())
    }

    /// Ближайшее место на ломаной. Мерить до вершин нельзя: после
    /// упрощения прямой участок — это две точки на пол-экрана.
    static func nearest(_ p: P, polyline: [P]) -> Projection {
        var best = Projection(segment: 0, t: 0, distance: .infinity)
        for i in 0..<(polyline.count - 1) {
            let r = project(p, onto: polyline[i], polyline[i + 1])
            if r.d < best.distance {
                best = Projection(segment: i, t: r.t, distance: r.d)
            }
        }
        return best
    }

    static func lerp(_ a: P, _ b: P, _ t: Double) -> P {
        P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }

    // MARK: мазок

    public enum StrokeOutcome: Equatable {
        case started            // первый мазок — начало маршрута
        case extended           // продлён ближайший конец
        case replacedSegment    // перечёркнутый участок заменён
        case rejected           // далеко от маршрута
    }

    public static func applyStroke(_ stroke: [P], to path: inout [P],
                                   snap: Double = 45) -> StrokeOutcome {
        guard stroke.count >= 2 else { return .rejected }
        if path.count < 2 {
            path = stroke
            return .started
        }

        let s0 = stroke[0], s1 = stroke[stroke.count - 1]
        let a = nearest(s0, polyline: path)
        let b = nearest(s1, polyline: path)

        // оба конца на линии — правка перечёркиванием
        if a.distance < snap && b.distance < snap {
            let (p1, p2, seg) = a.order <= b.order
                ? (a, b, stroke) : (b, a, Array(stroke.reversed()))
            let cut1 = lerp(path[p1.segment], path[p1.segment + 1], p1.t)
            let cut2 = lerp(path[p2.segment], path[p2.segment + 1], p2.t)
            path = Array(path[0...p1.segment]) + [cut1] + seg + [cut2]
                 + Array(path[(p2.segment + 1)...])
            return .replacedSegment
        }

        // продление с ближайшего конца
        func dist(_ x: P, _ y: P) -> Double {
            ((x.x - y.x) * (x.x - y.x) + (x.y - y.y) * (x.y - y.y)).squareRoot()
        }
        let head = path[0], tail = path[path.count - 1]
        let options: [(d: Double, atHead: Bool, add: [P])] = [
            (dist(s0, tail), false, stroke),
            (dist(s1, tail), false, stroke.reversed()),
            (dist(s0, head), true, stroke.reversed()),
            (dist(s1, head), true, stroke),
        ]
        let bestOpt = options.min { $0.d < $1.d }!
        if bestOpt.d > snap { return .rejected }
        path = bestOpt.atHead ? bestOpt.add + path : path + bestOpt.add
        return .extended
    }

    // MARK: ластик-нож

    public enum EraseOutcome: Equatable {
        case trimmed        // всё после места касания стёрто
        case cleared        // касание у начала — маршрут стёрт целиком
        case missed         // след не задел линию
    }

    public static func eraseCut(_ stroke: [P], path: inout [P],
                                radius: Double = 34) -> EraseOutcome {
        guard path.count >= 2, !stroke.isEmpty else { return .missed }
        var best: Projection? = nil
        for sp in stroke {
            let n = nearest(sp, polyline: path)
            if n.distance < radius && (best == nil || n.order < best!.order) {
                best = n
            }
        }
        guard let hit = best else { return .missed }
        let cut = lerp(path[hit.segment], path[hit.segment + 1], hit.t)
        var np = Array(path[0...hit.segment])
        let last = np[np.count - 1]
        if ((last.x - cut.x) * (last.x - cut.x)
          + (last.y - cut.y) * (last.y - cut.y)).squareRoot() > 1e-9 {
            np.append(cut)
        }
        if np.count < 2 {
            path = []
            return .cleared
        }
        path = np
        return .trimmed
    }
}
