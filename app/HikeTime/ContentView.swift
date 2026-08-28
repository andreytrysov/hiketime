import SwiftUI
import HikeTimeCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            MapView().ignoresSafeArea()

            VStack {
                if model.hasRoute { pill }
                Spacer()
                bottomPanel
            }

            VStack(spacing: 10) {
                Spacer()
                if model.hasRoute {
                    roundButton("arrow.uturn.backward") { model.undo() }
                    roundButton("xmark") { model.clear() }
                }
                if model.drawMode {
                    roundButton(model.eraseMode ? "pencil" : "eraser",
                                active: model.eraseMode) {
                        model.eraseMode.toggle()
                    }
                }
                roundButton("pencil", active: model.drawMode, big: true) {
                    model.drawMode.toggle()
                    if !model.drawMode { model.eraseMode = false }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
            .padding(.bottom, 170)
        }
    }

    private var pill: some View {
        VStack(spacing: 2) {
            Text(model.computing ? "…" : model.totalText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(model.statsText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.elevationError {
                Text("высоты не получены — нет сети?")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if model.hasRoute {
                HStack {
                    Text(model.movingText)
                    Spacer()
                    Text(model.breaksText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Text("Рюкзак")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.loadKg)) кг")
                    .font(.headline)
                    .monospacedDigit()
            }
            Slider(value: $model.loadKg, in: 0...40, step: 1)
                .tint(model.loadZone.0)
            HStack {
                Text(model.loadZone.1)
                    .font(.caption2)
                    .foregroundStyle(model.loadZone.0)
                Spacer()
                if model.hasRoute {
                    Text(model.sensText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Picker("Покрытие", selection: $model.terrain) {
                    Text("Тропа").tag(1.0)
                    Text("Тундра, кусты").tag(1.55)
                    Text("Болото, камни").tag(1.9)
                }
                Picker("Темп", selection: $model.power) {
                    Text("Медленно").tag(3.0)
                    Text("Обычно").tag(3.6)
                    Text("Быстро").tag(4.3)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func roundButton(_ icon: String, active: Bool = false,
                             big: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: big ? 22 : 17, weight: .medium))
                .frame(width: big ? 54 : 44, height: big ? 54 : 44)
                .background(active ? Color(red: 0.18, green: 0.44, blue: 0.31)
                                   : Color(.systemBackground).opacity(0.94),
                            in: RoundedRectangle(cornerRadius: big ? 16 : 12))
                .foregroundStyle(active ? .white : .primary)
                .shadow(radius: 4, y: 2)
        }
    }
}
