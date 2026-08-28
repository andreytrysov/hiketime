import SwiftUI
import HikeTimeCore

/// Онбординг по спецификации прототипа: три экрана, на каждом что-то
/// живое двигается. Контраст наив/модель — один раз, здесь его место.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var demoSegments: [Segment] = []
    @State private var demoLoad = 0.0
    @State private var body_ = 75.0

    /// Настоящая тропа Шварцзее → Хёрнлихютте; высоты — из вшитых тайлов.
    private static let demoRoute = [
        GeoPoint(lat: 45.9824, lon: 7.7025),
        GeoPoint(lat: 45.9793, lon: 7.6929),
        GeoPoint(lat: 45.9807, lon: 7.6855),
        GeoPoint(lat: 45.9822, lon: 7.6770),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                contrast.tag(0)
                weight.tag(1)
                bodyWeight.tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    model.bodyKg = body_
                    dismiss()
                }
            } label: {
                Text(page < 2 ? loc.t("Дальше") : loc.t("Начать"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent,
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            Button(loc.t("Пропустить")) { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
        }
        .task { await loadDemo() }
        .onAppear { body_ = model.bodyKg }
    }

    private func loadDemo() async {
        let store = TileStore()
        let dense = Geo.resample(Self.demoRoute, step: 25)
        guard let tiles = try? await store.tilesFor(points: dense, zoom: 12)
        else { return }
        if let prof = try? RouteBuilder.build(points: Self.demoRoute,
                                              provider: { key in
            guard let t = tiles[key] else {
                throw DEM.DEMError.tileUnavailable(key)
            }
            return t
        }) {
            demoSegments = prof.segments
        }
    }

    private func fmt(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    private var naive: String {
        let dist = demoSegments.reduce(0) { $0 + $1.distance }
        return fmt(dist / 1000 / 4)
    }

    private func modelTime(load: Double) -> String {
        fmt(EnergyModel(bodyKg: 75, loadKg: load).timeHours(demoSegments))
    }

    // 1: контраст
    private var contrast: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(loc.t("Обычные приложения делят расстояние на скорость"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(loc.t("Тропа к хижине Хёрнли под Маттерхорном. Справочное время — 2 часа."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                card(loc.t("расстояние ÷ скорость"), naive, .red)
                card(loc.t("с учётом рельефа"), modelTime(load: 0),
                     Theme.accent)
            }
            Text(loc.t("Разница — почти втрое. Это и есть смысл приложения."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func card(_ label: String, _ value: String,
                      _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // 2: вес рюкзака
    private var weight: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(loc.t("Рюкзак меняет время сильнее, чем кажется"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(loc.t("Тот же маршрут. Подвигайте ползунок."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(modelTime(load: demoLoad))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(demoLoad == 0 ? loc.t("налегке")
                 : "\(Int(demoLoad)) \(loc.t("кг"))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $demoLoad, in: 0...30, step: 1)
                .tint(Theme.accent)
                .padding(.horizontal, 10)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // 3: вес тела
    private var bodyWeight: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(loc.t("Сколько вы весите?"))
                .font(.title2.bold())
            Text(loc.t("Пороги нагрузки считаются в процентах от массы тела. Можно пропустить."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Picker("", selection: $body_) {
                ForEach(35...160, id: \.self) { kg in
                    Text("\(kg) \(loc.t("кг"))").tag(Double(kg))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
