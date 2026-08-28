import SwiftUI
import Charts
import HikeTimeCore

/// Нижняя шторка с тремя позициями — как в прототипе:
/// середина — ввод (рюкзак, покрытие, темп), полная — анализ
/// (профиль высот, плитки). Тянется за ручку.
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
                .padding(.bottom, 8)

            VStack(spacing: 10) {
                chips
                weightBlock
                pickersRow
                if position == .full {
                    analysis
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial,
                    in: UnevenRoundedRectangle(topLeadingRadius: 18,
                                               topTrailingRadius: 18))
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

    // MARK: чипы «в движении · привалы · обед»

    private var chips: some View {
        HStack(spacing: 6) {
            chip(loc.t("в движении"), model.movingHoursText)
            if model.shortBreaks > 0 {
                chip(loc.t("привалы"), "\(model.shortBreaks) × 10 \(loc.t("мин"))")
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
        .font(.caption)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: рюкзак

    private var zoneText: String {
        let p = model.loadKg / model.bodyKg * 100
        let key: String
        switch p {
        case ..<10: key = "% массы тела — вес почти не мешает"
        case ..<20: key = "% массы тела — нормальная многодневка"
        case ..<25: key = "% массы тела — тяжело, риск растёт"
        case ..<30: key = "% массы тела — расход выше на треть"
        default: key = "% массы тела — так ходить не надо"
        }
        return String(format: "%.0f", p) + loc.t(key)
    }

    private var weightBlock: some View {
        VStack(spacing: 4) {
            HStack {
                Text(loc.t("Рюкзак"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.loadKg)) \(loc.t("кг"))")
                    .font(.headline)
                    .monospacedDigit()
            }
            Slider(value: $model.loadKg, in: 0...40, step: 1)
                .tint(Theme.zone(model.loadKg / model.bodyKg * 100))
            HStack {
                Text(zoneText)
                    .font(.caption2)
                    .foregroundStyle(Theme.zone(model.loadKg / model.bodyKg * 100))
                Spacer()
                Text(loc.f("+1 кг = +%d мин", model.sensMinutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

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

    private var pickersRow: some View {
        HStack(spacing: 8) {
            CompactSelect(value: terrainTitle,
                          options: [loc.t("Тропа"), loc.t("Тундра, кусты"),
                                    loc.t("Болото, камни")]) { p in
                if p == loc.t("Тундра, кусты") { model.terrain = 1.55 }
                else if p == loc.t("Болото, камни") { model.terrain = 1.9 }
                else { model.terrain = 1.0 }
            }
            .frame(maxWidth: .infinity)
            CompactSelect(value: paceTitle,
                          options: [loc.t("Медленно"), loc.t("Обычно"),
                                    loc.t("Быстро")]) { p in
                if p == loc.t("Медленно") { model.power = 3.0 }
                else if p == loc.t("Быстро") { model.power = 4.3 }
                else { model.power = 3.6 }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: анализ (полная позиция)

    private var analysis: some View {
        VStack(spacing: 10) {
            profileChart
            tiles
        }
    }

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
                    Text(String(format: "%.1f км · %.0f м",
                                model.chartDistKm[i], prof.elevations[i]))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            if let prof = model.profile, model.chartDistKm.count > 1 {
                let pts = Array(zip(model.chartDistKm, prof.elevations))
                Chart {
                    ForEach(pts.indices, id: \.self) { i in
                        AreaMark(x: .value("км", pts[i].0),
                                 y: .value("м", pts[i].1))
                            .foregroundStyle(
                                Theme.accent.opacity(0.15))
                        LineMark(x: .value("км", pts[i].0),
                                 y: .value("м", pts[i].1))
                            .foregroundStyle(
                                Theme.accent)
                    }
                    if let i = model.highlightIndex, i < pts.count {
                        PointMark(x: .value("км", pts[i].0),
                                  y: .value("м", pts[i].1))
                            .foregroundStyle(.primary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
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

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: 8) {
            tile(loc.t("набор"), String(format: "%.0f %@", model.gainMeters, loc.t("единица_м")))
            tile(loc.t("сброс"), String(format: "%.0f %@", model.lossMeters, loc.t("единица_м")))
            tile(loc.t("средний темп"), String(format: "%.1f %@", model.paceKmh, loc.t("единица_кмч")))
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
