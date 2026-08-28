import SwiftUI
import HikeTimeCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var loc = Loc()
    @StateObject private var store = RoutesStore()

    enum Panel { case none, routes, settings, layers }
    @State private var panel: Panel = .none

    @State private var askName = false
    @State private var draftName = ""
    @State private var askClear = false
    @State private var deleteCandidate: SavedRoute?
    @State private var showOnboarding = false
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            MapView().ignoresSafeArea()

            VStack {
                if model.hasRoute { pill }
                else if !model.drawMode { emptyHint }
                Spacer()
                if model.hasRoute { SheetView() }
            }

            leftColumn
            rightColumn
            topRightColumn

            // лёгкие карточки-панели вместо системных шитов
            if panel != .none {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { panel = .none }
            }
            Group {
                if panel == .routes { routesPanel }
                if panel == .settings { settingsPanel }
                if panel == .layers { layersPanel }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.easeOut(duration: 0.15), value: panel)

            if let toast = model.toastText {
                VStack {
                    Spacer()
                    Text(loc.t(toast))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.82),
                                    in: RoundedRectangle(cornerRadius: 11))
                        .padding(.bottom, 240)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: model.toastText)
            }
        }
        .environmentObject(loc)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(loc)
        }
        .onAppear {
            if !onboarded {
                showOnboarding = true
                onboarded = true
            }
        }
        .alert(loc.t("Название маршрута"), isPresented: $askName) {
            TextField(loc.t("Маршрут"), text: $draftName)
            Button(loc.t("Сохранить")) { saveCurrent() }
            Button(loc.t("Отмена"), role: .cancel) {}
        }
        .alert(loc.t("Стереть нарисованный маршрут?"), isPresented: $askClear) {
            Button(loc.t("Стереть"), role: .destructive) { model.clear() }
            Button(loc.t("Отмена"), role: .cancel) {}
        }
        .alert(loc.f("Удалить «%@»?", deleteCandidate?.name ?? ""),
               isPresented: .init(get: { deleteCandidate != nil },
                                  set: { if !$0 { deleteCandidate = nil } })) {
            Button(loc.t("Удалить"), role: .destructive) {
                if let r = deleteCandidate { store.delete(r) }
                deleteCandidate = nil
            }
            Button(loc.t("Отмена"), role: .cancel) { deleteCandidate = nil }
        }
    }

    // MARK: колонки кнопок (раскладка прототипа)

    private var leftColumn: some View {
        VStack(spacing: 10) {
            MapButton(icon: "line.3.horizontal") { toggle(.routes) }
            MapButton(icon: "gearshape") { toggle(.settings) }
            Spacer()
            MapButton(icon: model.followUser ? "location.fill" : "location",
                      active: model.followUser) {
                model.followUser.toggle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.top, 8)
        .padding(.bottom, model.hasRoute ? 250 : 40)
        .opacity(model.sheetExpanded ? 0 : 1)
    }

    private var topRightColumn: some View {
        VStack {
            MapButton(icon: "square.3.layers.3d",
                      active: panel == .layers) { toggle(.layers) }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        .padding(.top, 8)
    }

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Spacer()
            if model.hasRoute {
                // удаление — всегда верхнее из инструментов
                MapButton(icon: "xmark", tint: Theme.danger) { askClear = true }
                ShareLink(item: RouteShare.url(path: model.path,
                                               loadKg: model.loadKg,
                                               terrain: model.terrain,
                                               power: model.power)) {
                    MapButtonLabel(icon: "arrowshape.turn.up.right")
                }
                .buttonStyle(.plain)
                MapButton(icon: model.savedId != nil ? "checkmark" : "floppy",
                          active: model.savedId != nil) {
                    if model.savedId == nil {
                        draftName = model.routeName ?? defaultName
                        askName = true
                    }
                }
                MapButton(icon: "arrow.uturn.backward") { model.undo() }
            }
            HStack(spacing: 10) {
                if model.drawMode {
                    MapButton(icon: "eraser", active: model.eraseMode) {
                        model.eraseMode.toggle()
                    }
                }
                MapButton(icon: "pencil", active: model.drawMode,
                          big: true) {
                    model.drawMode.toggle()
                    if model.drawMode {
                        model.toast("Один палец рисует, два — двигают карту")
                    } else {
                        model.eraseMode = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        .padding(.bottom, model.hasRoute ? 250 : 40)
        .opacity(model.sheetExpanded ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: model.sheetExpanded)
    }

    private func toggle(_ p: Panel) {
        panel = panel == p ? .none : p
    }

    // MARK: карточки-панели

    private var routesPanel: some View {
        PanelCard(alignment: .topLeading) {
            if model.hasRoute {
                ShareLink(item: RouteShare.url(path: model.path,
                                               loadKg: model.loadKg,
                                               terrain: model.terrain,
                                               power: model.power)) {
                    Text(loc.t("Поделиться ссылкой"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider()
            }
            Text(loc.t("Мои маршруты").uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            if store.routes.isEmpty {
                Text(loc.t("Пока пусто — нарисуйте и сохраните"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if store.routes.count > 4 {
                ScrollView { routeRows }
                    .frame(height: 250)
            } else {
                routeRows
            }
        }
    }

    private var settingsPanel: some View {
        PanelCard(alignment: .topLeading) {
            Text(loc.t("Настройки").uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(loc.t("Вес тела"))
                    .font(.subheadline)
                Spacer()
                SelectBox(value: "\(Int(model.bodyKg))",
                          options: (35...160).map { "\($0)" }) { picked in
                    if let v = Double(picked) { model.bodyKg = v }
                }
                .frame(width: 86)
                Text(loc.t("кг"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 8) {
                Text(loc.t("Язык"))
                    .font(.subheadline)
                Spacer()
                SelectBox(value: languageTitle,
                          options: [loc.t("Системный"), "Русский", "English"]) { picked in
                    switch picked {
                    case "Русский": loc.language = AppLanguage.ru.rawValue
                    case "English": loc.language = AppLanguage.en.rawValue
                    default: loc.language = AppLanguage.system.rawValue
                    }
                }
                .frame(width: 132)
            }
            Divider()
            Button {
                panel = .none
                showOnboarding = true
            } label: {
                Text(loc.t("Как это работает"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private var languageTitle: String {
        switch AppLanguage(rawValue: loc.language) ?? .system {
        case .system: return loc.t("Системный")
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    private var layersPanel: some View {
        PanelCard(alignment: .topTrailing) {
            Text(loc.t("Подложка").uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            layerRow(loc.t("Рельеф (оффлайн)"),
                     selected: model.baseLayer == "hillshade") {
                model.baseLayer = "hillshade"
            }
            layerRow(loc.t("Топо (онлайн)"),
                     selected: model.baseLayer == "topo") {
                model.baseLayer = "topo"
            }
            layerRow(loc.t("Обычная (онлайн)"),
                     selected: model.baseLayer == "plain") {
                model.baseLayer = "plain"
            }
            layerRow(loc.t("Спутник (онлайн)"),
                     selected: model.baseLayer == "satellite") {
                model.baseLayer = "satellite"
            }
            Divider()
            Text(loc.t("Поверх").uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            if model.baseLayer == "hillshade" || model.baseLayer == "satellite" {
                layerRow(loc.t("Линии высот"),
                         selected: model.contours) {
                    model.contours.toggle()
                }
            } else {
                Text(loc.t("Линии высот"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
            }
            Divider()
            Text(loc.t("Маршрут").uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            layerRow(loc.t("Цвет по скорости"),
                     selected: model.speedColor) {
                model.speedColor.toggle()
            }
        }
    }

    private var routeRows: some View {
        VStack(spacing: 0) {
            ForEach(store.routes) { r in
                HStack {
                    Button {
                        open(r)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(String(format: "%.1f", r.distM/1000)) \(loc.t("единица_км")) · \(r.timeText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        deleteCandidate = r
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func layerRow(_ text: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(selected ? Theme.accent : .primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(selected ? Theme.accent.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: сохранение и открытие

    private var defaultName: String {
        let km = (model.profile?.distM ?? 0) / 1000
        return "\(loc.t("Маршрут")) \(String(format: "%.1f", km)) \(loc.t("единица_км"))"
    }

    private func saveCurrent() {
        guard let prof = model.profile else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let r = store.add(name: name.isEmpty ? defaultName : name,
                          path: model.path, loadKg: model.loadKg,
                          terrain: model.terrain, power: model.power,
                          distM: prof.distM, timeText: model.totalText)
        model.routeName = r.name
        model.savedId = r.id
    }

    private func open(_ r: SavedRoute) {
        model.path = r.path.map { GeoPoint(lat: $0[0], lon: $0[1]) }
        model.loadKg = r.loadKg
        model.terrain = r.terrain
        model.power = r.power
        model.routeName = r.name
        model.savedId = r.id
        model.recomputeProfile()
        model.fitRequest += 1
        panel = .none
    }

    // MARK: плашка и пустое состояние

    private var pill: some View {
        VStack(spacing: 2) {
            if let name = model.routeName {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(model.computing ? "…" : model.totalText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(model.statsLocalized(loc))
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.elevationError {
                Text(loc.t("высоты не получены — нет сети?"))
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
        .frame(maxWidth: 280)
    }

    private var emptyHint: some View {
        Text(loc.t("Нажмите ✎ и нарисуйте маршрут пальцем"))
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 250)
            .padding(.top, 8)
    }
}

/// Плавающая карточка-панель в стиле прототипа.
struct PanelCard<Content: View>: View {
    let alignment: Alignment
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .frame(width: 262, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM)
                .strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, 14)
        .padding(.top, 64)
    }
}

struct PanelRow: View {
    let icon: String
    let text: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Компактный «селект» прототипа: капсула со значением и шевроном.
struct CompactSelect: View {
    let value: String
    let options: [String]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button(o) { onPick(o) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}
