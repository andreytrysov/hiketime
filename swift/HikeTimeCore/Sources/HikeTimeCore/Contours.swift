import Foundation

/// Горизонтали из сетки высот: marching squares, сцепка отрезков в
/// полилинии, упрощение. Порт того, чем собирался вшитый пакет —
/// теперь считается на устройстве для скачанных районов.
public enum Contours {

    /// Сетка высот: row-major, размер width×height.
    public struct Grid {
        public let values: [Double]
        public let width: Int
        public let height: Int
        public init(values: [Double], width: Int, height: Int) {
            self.values = values
            self.width = width
            self.height = height
        }
        @inline(__always) func at(_ x: Int, _ y: Int) -> Double {
            values[y * width + x]
        }
    }

    public struct Line {
        public let elevation: Double
        public let major: Bool
        /// Точки в координатах сетки (x, y), доли пикселей.
        public let points: [(Double, Double)]
    }

    /// Все изолинии с шагом step; каждая кратная majorEvery — «жирная».
    public static func build(grid: Grid, step: Double = 100,
                             majorEvery: Double = 500,
                             simplifyTolerance: Double = 0.7) -> [Line] {
        guard let lo = grid.values.min(), let hi = grid.values.max(),
              hi > lo else { return [] }
        var out: [Line] = []
        var level = (lo / step).rounded(.down) * step + step
        while level < hi {
            let segs = segments(grid: grid, level: level)
            for chainPts in chain(segs) where chainPts.count >= 4 {
                // фильтруем ПОСЛЕ упрощения: оно может схлопнуть
                // короткий фрагмент до отрезка, а это уже не горизонталь
                let simplified = simplify(chainPts, tolerance: simplifyTolerance)
                guard simplified.count >= 3 else { continue }
                out.append(Line(elevation: level,
                                major: level.truncatingRemainder(
                                    dividingBy: majorEvery) == 0,
                                points: simplified))
            }
            level += step
        }
        return out
    }

    // MARK: marching squares

    typealias Pt = (Double, Double)

    static func segments(grid: Grid, level: Double) -> [(Pt, Pt)] {
        var segs: [(Pt, Pt)] = []
        for cy in 0..<(grid.height - 1) {
            for cx in 0..<(grid.width - 1) {
                let vTL = grid.at(cx, cy), vTR = grid.at(cx + 1, cy)
                let vBL = grid.at(cx, cy + 1), vBR = grid.at(cx + 1, cy + 1)
                var idx = 0
                if vTL >= level { idx |= 8 }
                if vTR >= level { idx |= 4 }
                if vBR >= level { idx |= 2 }
                if vBL >= level { idx |= 1 }
                guard idx > 0 && idx < 15 else { continue }

                func lerp(_ a: Pt, _ b: Pt, _ va: Double, _ vb: Double) -> Pt {
                    let t = vb == va ? 0.5 : (level - va) / (vb - va)
                    return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
                }
                let x = Double(cx), y = Double(cy)
                let top = lerp((x, y), (x + 1, y), vTL, vTR)
                let bottom = lerp((x, y + 1), (x + 1, y + 1), vBL, vBR)
                let left = lerp((x, y), (x, y + 1), vTL, vBL)
                let right = lerp((x + 1, y), (x + 1, y + 1), vTR, vBR)

                switch idx {
                case 1: segs.append((bottom, left))
                case 2: segs.append((right, bottom))
                case 3: segs.append((right, left))
                case 4: segs.append((top, right))
                case 5: segs.append((top, left)); segs.append((right, bottom))
                case 6: segs.append((top, bottom))
                case 7: segs.append((top, left))
                case 8: segs.append((left, top))
                case 9: segs.append((bottom, top))
                case 10: segs.append((left, bottom)); segs.append((top, right))
                case 11: segs.append((right, top))
                case 12: segs.append((left, right))
                case 13: segs.append((bottom, right))
                case 14: segs.append((left, bottom))
                default: break
                }
            }
        }
        return segs
    }

    /// Сцепка отрезков в непрерывные линии по совпадающим концам.
    static func chain(_ segs: [(Pt, Pt)]) -> [[Pt]] {
        struct Key: Hashable { let x: Int; let y: Int }
        func key(_ p: Pt) -> Key {
            Key(x: Int((p.0 * 100).rounded()), y: Int((p.1 * 100).rounded()))
        }
        var adjacency: [Key: [Int]] = [:]
        for (i, s) in segs.enumerated() {
            adjacency[key(s.0), default: []].append(i)
            adjacency[key(s.1), default: []].append(i)
        }
        var used = [Bool](repeating: false, count: segs.count)
        var lines: [[Pt]] = []

        for start in segs.indices where !used[start] {
            used[start] = true
            var line = [segs[start].0, segs[start].1]

            // тянем в обе стороны, пока находится сосед
            var grown = true
            while grown {
                grown = false
                for end in [true, false] {
                    let tip = end ? line[line.count - 1] : line[0]
                    guard let cands = adjacency[key(tip)] else { continue }
                    for i in cands where !used[i] {
                        let s = segs[i]
                        let next: Pt
                        if key(s.0) == key(tip) { next = s.1 }
                        else if key(s.1) == key(tip) { next = s.0 }
                        else { continue }
                        used[i] = true
                        if end { line.append(next) } else { line.insert(next, at: 0) }
                        grown = true
                        break
                    }
                }
            }
            lines.append(line)
        }
        return lines
    }

    /// Дуглас–Пекер по точкам сетки.
    static func simplify(_ pts: [Pt], tolerance: Double) -> [Pt] {
        guard pts.count >= 3 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        func d2(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
            var x = a.0, y = a.1
            let dx = b.0 - a.0, dy = b.1 - a.1
            if dx != 0 || dy != 0 {
                let t = ((p.0 - x) * dx + (p.1 - y) * dy) / (dx * dx + dy * dy)
                if t > 1 { x = b.0; y = b.1 }
                else if t > 0 { x += dx * t; y += dy * t }
            }
            let ex = p.0 - x, ey = p.1 - y
            return ex * ex + ey * ey
        }
        func rec(_ i: Int, _ j: Int) {
            var maxD = 0.0, idx = -1
            if j - i < 2 { return }
            for k in (i + 1)..<j {
                let d = d2(pts[k], pts[i], pts[j])
                if d > maxD { maxD = d; idx = k }
            }
            if maxD > tolerance * tolerance, idx > 0 {
                keep[idx] = true
                rec(i, idx)
                rec(idx, j)
            }
        }
        rec(0, pts.count - 1)
        return pts.indices.compactMap { keep[$0] ? pts[$0] : nil }
    }
}
