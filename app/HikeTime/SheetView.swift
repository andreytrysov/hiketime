import SwiftUI
import Charts
import HikeTimeCore

/// Нижняя шторка — визуально один в один с веб-прототипом.
struct SheetView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc

    enum Position { case half, full }
    @State private var position: Position = .half
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 38, height: 4)
                .padding(.top, 9)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                chips
                weightBlock
                selectsRow
                if position == .full {
                    profileChart
                    tiles
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            // сплошной фон, как в прототипе: на материале плитки растворялись
            UnevenRoundedRectangle(topLeadingRadius: 18,
                                   topTrailingRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.10), radius: 10, y: -3)
                .ignoresSafeArea(edges: .bottom)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(-40, $0.translation.height * 0.6) }
                .onEnded { v in
                    withAnimation(.spring(duration: 0.3)) {
                        if v.translation.height < -30 { position = .full }
                        else if v.translation.height > 30 { position = .half }
                        dragOffset = 0
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(duration: 0.3)) {
                position = position == .half ? .full : .half
            }
        }
        .onChange(of: position) { p in
            model.sheetExpanded = p == .full
        }
        .onDisappear { model.sheetExpanded = false }
    }

    // MARK: чипы

    private var chips: some View {
        HStack(spacing: 8) {
            chip(loc.t("в движении"), model.movingHoursText)
            if model.shortBreaks > 0 {
                chip(loc.t("привалы"),
                     "\(model.shortBreaks) × 10 \(loc.t("мин"))")
            } else {
                chip("", loc.t("без привалов"))
            }
            if model.lunch {
                chip("", loc.t("обед 30 мин"))
            }
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label).foregroundStyle(.secondary)
            }
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: рюкзак

    private var zonePercent: Double { model.loadKg / model.bodyKg * 100 }

    private var zoneText: String {
        let key: String
        switch zonePercent {
        case ..<10: key = "% массы тела — вес почти не мешает"
        case ..<20: key = "% массы тела — нормальная многодневка"
        case ..<25: key = "% массы тела — тяжело, риск растёт"
        case ..<30: key = "% массы тела — расход выше на треть"
        default: key = "% массы тела — так ходить не надо"
        }
        var out = String(format: "%.0f", zonePercent) + loc.t(key)
        if model.hasRoute {
            out += " · " + loc.f("+1 кг = +%d мин", model.sensMinutes)
        }
        return out
    }

    private var weightBlock: some View {
        VStack(spacing: 6) {
            HStack {
                Text(loc.t("Рюкзак"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.loadKg)) \(loc.t("кг"))")
                    .font(.headline)
                    .monospacedDigit()
            }
            ZoneSlider(value: $model.loadKg, range: 0...40,
                       fill: Theme.zone(zonePercent),
                       ticks: [10, 20, 25, 30].map { model.bodyKg * $0 / 100 })
            HStack {
                Text(zoneText)
                    .font(.caption)
                    .foregroundStyle(Theme.zone(zonePercent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }
        }
    }

    // MARK: селекты с подписями (как в прототипе)

    private var terrainTitle: String {
        switch model.terrain {
        case 1.55: return loc.t("Тундра, кусты")
        case 1.9: return loc.t("Болото, камни")
        default: return loc.t("Тропа")
        }
    }

    private var paceTitle: String {
        switch model.power {
        case 3.0: return loc.t("Медленно")
        case 4.3: return loc.t("Быстро")
        default: return loc.t("Обычно")
        }
    }

    private var selectsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Покрытие"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SelectBox(value: terrainTitle,
                          options: [loc.t("Тропа"), loc.t("Тундра, кусты"),
                                    loc.t("Болото, камни")]) { p in
                    if p == loc.t("Тундра, кусты") { model.terrain = 1.55 }
                    else if p == loc.t("Болото, камни") { model.terrain = 1.9 }
                    else { model.terrain = 1.0 }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Темп"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SelectBox(value: paceTitle,
                          options: [loc.t("Медленно"), loc.t("Обычно"),
                                    loc.t("Быстро")]) { p in
                    if p == loc.t("Медленно") { model.power = 3.0 }
                    else if p == loc.t("Быстро") { model.power = 4.3 }
                    else { model.power = 3.6 }
                }
            }
        }
    }

    // MARK: профиль

    private var profileChart: some View {
        VStack(spacing: 2) {
            HStack {
                Text(loc.t("Профиль высот"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let i = model.highlightIndex,
                   let prof = model.profile,
                   i < prof.elevations.count, i < model.chartDistKm.count {
                    Text(String(format: "%.1f \(loc.t("единица_км")) · %.0f \(loc.t("единица_м"))",
                                model.chartDistKm[i], prof.elevations[i]))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            if let prof = model.profile, model.chartDistKm.count > 1 {
                let pts = Array(zip(model.chartDistKm, prof.elevations))
                let lo = prof.elevations.min() ?? 0
                let hi = prof.elevations.max() ?? 1
                let pad = max((hi - lo) * 0.08, 10)
                Chart {
                    ForEach(pts.indices, id: \.self) { i in
                        AreaMark(x: .value("км", pts[i].0),
                                 yStart: .value("м", lo - pad),
                                 yEnd: .value("м", pts[i].1))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent.opacity(0.13))
                        LineMark(x: .value("км", pts[i].0),
                                 y: .value("м", pts[i].1))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    if let i = model.highlightIndex, i < pts.count {
                        PointMark(x: .value("км", pts[i].0),
                                  y: .value("м", pts[i].1))
                            .foregroundStyle(.primary)
                    }
                }
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .chartXScale(domain: 0...(model.chartDistKm.last ?? 1))
                .chartYAxis(.hidden)
                .chartXAxis {
                    let total = model.chartDistKm.last ?? 1
                    let step: Double = total <= 6 ? 1 : total <= 14 ? 2 : 5
                    AxisMarks(values: Array(stride(from: 0, through: total,
                                                   by: step))) {
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .chartPlotStyle { $0.background(.clear) }
                .frame(height: 110)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        if let km: Double = proxy.value(
                                            atX: v.location.x - origin.x) {
                                            highlight(km: km)
                                        }
                                    }
                                    .onEnded { _ in
                                        model.highlightIndex = nil
                                    }
                            )
                    }
                }
            }
        }
    }

    private func highlight(km: Double) {
        let dists = model.chartDistKm
        guard !dists.isEmpty else { return }
        var best = 0
        var bestD = Double.infinity
        for (i, d) in dists.enumerated() where abs(d - km) < bestD {
            bestD = abs(d - km)
            best = i
        }
        model.highlightIndex = best
    }

    // MARK: плитки

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 8) {
            tile(loc.t("набор"),
                 String(format: "%.0f %@", model.gainMeters, loc.t("единица_м")))
            tile(loc.t("сброс"),
                 String(format: "%.0f %@", model.lossMeters, loc.t("единица_м")))
            tile(loc.t("средний темп"),
                 String(format: "%.1f %@", model.paceKmh, loc.t("единица_кмч")))
            tile(loc.t("без учёта рельефа"), model.naiveText)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Селект прототипа: рамка, значение слева, шеврон вниз справа.
struct SelectBox: View {
    let value: String
    let options: [String]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button(o) { onPick(o) }
            }
        } label: {
            HStack {
                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.systemGray4), lineWidth: 1))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}

/// Слайдер прототипа: цветная заливка зоны и риски порогов на треке.
struct ZoneSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fill: Color
    let ticks: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = (value - range.lowerBound)
                     / (range.upperBound - range.lowerBound)
            let x = w * frac
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 6)
                Capsule()
                    .fill(fill)
                    .frame(width: max(x, 6), height: 6)
                ForEach(ticks, id: \.self) { t in
                    let tf = (t - range.lowerBound)
                           / (range.upperBound - range.lowerBound)
                    if tf > 0.01 && tf < 0.99 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.black.opacity(0.18))
                            .frame(width: 2, height: 12)
                            .position(x: w * tf, y: geo.size.height / 2)
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .position(x: min(max(x, 13), w - 13),
                              y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(g.location.x / w, 0), 1)
                        let raw = range.lowerBound
                                + f * (range.upperBound - range.lowerBound)
                        value = raw.rounded()
                    }
            )
        }
        .frame(height: 30)
    }
}
