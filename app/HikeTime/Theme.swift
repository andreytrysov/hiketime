import SwiftUI

/// Дизайн-токены. Родной HIG + свои константы; иконки — SF Symbols.
/// Палитра от глубокого хвойного: спокойная, «походная», без неона.
enum Theme {
    // цвет
    static let accent = Color(light: Color(red: 0.16, green: 0.42, blue: 0.30),
                              dark: Color(red: 0.36, green: 0.65, blue: 0.50))
    static let routeUI = UIColor(red: 0.16, green: 0.42, blue: 0.30, alpha: 1)
    static let danger = Color(red: 0.72, green: 0.25, blue: 0.20)
    static let warn = Color(red: 0.75, green: 0.55, blue: 0.10)

    // геометрия
    static let radiusS: CGFloat = 12
    static let radiusM: CGFloat = 16
    static let radiusL: CGFloat = 20
    static let button: CGFloat = 46
    static let buttonBig: CGFloat = 56

    static func zone(_ percent: Double) -> Color {
        switch percent {
        case ..<20: return accent
        case ..<25: return warn
        default: return danger
        }
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// Дискета — как в прототипе; в SF Symbols её нет.
struct FloppyIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let c = w * 0.22                      // срез уголка
        p.move(to: CGPoint(x: 0, y: h * 0.12))
        p.addLine(to: CGPoint(x: 0, y: h * 0.88))
        p.addQuadCurve(to: CGPoint(x: w * 0.12, y: h),
                       control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w * 0.88, y: h))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.88),
                       control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w, y: c))
        p.addLine(to: CGPoint(x: w - c, y: 0))
        p.addLine(to: CGPoint(x: w * 0.12, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.12),
                       control: CGPoint(x: 0, y: 0))
        // шторка и корпус этикетки
        p.move(to: CGPoint(x: w * 0.25, y: 0))
        p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.32))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.32))
        p.addLine(to: CGPoint(x: w * 0.68, y: 0))
        p.move(to: CGPoint(x: w * 0.22, y: h))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.58))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.58))
        p.addLine(to: CGPoint(x: w * 0.78, y: h))
        return p
    }
}

/// Ярлык круглой кнопки — используется и кнопками, и ShareLink.
struct MapButtonLabel: View {
    let icon: String
    var active = false
    var big = false
    var tint: Color? = nil

    @ViewBuilder private var glyph: some View {
        if icon == "floppy" {
            FloppyIcon()
                .stroke(style: StrokeStyle(lineWidth: 1.7,
                                           lineCap: .round,
                                           lineJoin: .round))
                .frame(width: 17, height: 17)
        } else {
            Image(systemName: icon)
                .font(.system(size: big ? 21 : 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }

    var body: some View {
        glyph
            .frame(width: big ? Theme.buttonBig : Theme.button,
                   height: big ? Theme.buttonBig : Theme.button)
            .background(
                active ? AnyShapeStyle(Theme.accent)
                       : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: big ? Theme.radiusM
                                                       : Theme.radiusS))
            .overlay(
                RoundedRectangle(cornerRadius: big ? Theme.radiusM
                                                   : Theme.radiusS)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
            .foregroundStyle(active ? .white : (tint ?? .primary))
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
    }
}

/// Круглая кнопка карты.
struct MapButton: View {
    let icon: String
    var active = false
    var big = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MapButtonLabel(icon: icon, active: active, big: big, tint: tint)
        }
        .buttonStyle(.plain)
    }
}
