import Foundation
import CoreGraphics
import ImageIO

/// Высоты из тайлов terrarium (формат Mapzen/AWS Open Data).
/// Высота в пикселе: (R*256 + G + B/256) - 32768.
/// z12 достаточно: выше — те же данные, растянутые (проверено на прототипе).
public enum DEM {

    public struct TileKey: Hashable, Sendable {
        public let z: Int, x: Int, y: Int
        public init(z: Int, x: Int, y: Int) { self.z = z; self.x = x; self.y = y }
    }

    /// Географические координаты -> глобальные пиксели тайловой сетки.
    public static func toGlobalPixels(lat: Double, lon: Double, zoom: Int)
        -> (x: Double, y: Double) {
        let n = pow(2.0, Double(zoom)) * 256
        let x = (lon + 180) / 360 * n
        let s = sin(lat * .pi / 180)
        let y = (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * n
        return (x, y)
    }

    /// Развёрнутый в память тайл: 256×256 высот.
    public struct Tile: Sendable {
        let elevations: [Double]   // row-major, 256*256

        public init?(pngData: Data) {
            guard let src = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  img.width == 256, img.height == 256 else { return nil }
            var raw = [UInt8](repeating: 0, count: 256 * 256 * 4)
            guard let ctx = CGContext(
                data: &raw, width: 256, height: 256,
                bitsPerComponent: 8, bytesPerRow: 256 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            var elev = [Double](repeating: 0, count: 256 * 256)
            for i in 0..<(256 * 256) {
                let r = Double(raw[i * 4])
                let g = Double(raw[i * 4 + 1])
                let b = Double(raw[i * 4 + 2])
                elev[i] = r * 256 + g + b / 256 - 32768
            }
            self.elevations = elev
        }

        public func at(_ px: Int, _ py: Int) -> Double {
            elevations[py * 256 + px]
        }
    }

    /// Источник тайлов: в приложении — локальный файл/пакет, в тестах — фикстура.
    public typealias TileProvider = (TileKey) throws -> Tile

    public enum DEMError: Error { case tileUnavailable(TileKey) }

    /// Билинейная интерполяция высоты. Повторяет Python-эталон бит в бит
    /// по формуле: центр пикселя смещён на полпикселя.
    public static func elevation(lat: Double, lon: Double, zoom: Int = 12,
                                 provider: TileProvider) throws -> Double {
        let g = toGlobalPixels(lat: lat, lon: lon, zoom: zoom)
        let fx = g.x - 0.5, fy = g.y - 0.5
        let x0 = Int(floor(fx)), y0 = Int(floor(fy))
        let dx = fx - Double(x0), dy = fy - Double(y0)

        var cache: [TileKey: Tile] = [:]
        func value(_ gx: Int, _ gy: Int) throws -> Double {
            let key = TileKey(z: zoom, x: gx / 256, y: gy / 256)
            let tile: Tile
            if let t = cache[key] { tile = t }
            else { tile = try provider(key); cache[key] = tile }
            return tile.at(gx % 256, gy % 256)
        }
        let v00 = try value(x0, y0), v10 = try value(x0 + 1, y0)
        let v01 = try value(x0, y0 + 1), v11 = try value(x0 + 1, y0 + 1)
        let top = v00 * (1 - dx) + v10 * dx
        let bot = v01 * (1 - dx) + v11 * dx
        return top * (1 - dy) + bot * dy
    }
}
