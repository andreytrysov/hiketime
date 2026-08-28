import Foundation
import SwiftUI

/// Язык интерфейса: системный или явный выбор.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ru, en
    var id: String { rawValue }
}

/// Локализация без внешних каталогов: два словаря, ключи — русские фразы.
/// Русский — исходный язык проекта, английский — перевод.
@MainActor
final class Loc: ObservableObject {
    @AppStorage("appLanguage") var language: String = AppLanguage.system.rawValue {
        willSet { objectWillChange.send() }
    }

    private static let en: [String: String] = [
        "Рюкзак": "Pack",
        "кг": "kg",
        "Тропа": "Trail",
        "Тундра, кусты": "Tundra, brush",
        "Болото, камни": "Bog, rocks",
        "Медленно": "Slow",
        "Обычно": "Normal",
        "Быстро": "Fast",
        "в движении": "moving",
        "привалы": "breaks",
        "обед 30 мин": "lunch 30 min",
        "без привалов": "no breaks",
        "мин": "min",
        "высоты не получены — нет сети?": "no elevation data — offline?",
        "Мои маршруты": "My routes",
        "Пока пусто — нарисуйте и сохраните": "Nothing yet — draw and save",
        "Сохранить маршрут": "Save route",
        "Название маршрута": "Route name",
        "Маршрут": "Route",
        "Сохранить": "Save",
        "Отмена": "Cancel",
        "Удалить": "Delete",
        "Удалить «%@»?": "Delete “%@”?",
        "Стереть нарисованный маршрут?": "Erase the drawn route?",
        "Стереть": "Erase",
        "Поделиться ссылкой": "Share link",
        "Настройки": "Settings",
        "Вес тела": "Body weight",
        "Язык": "Language",
        "Системный": "System",
        "Русский": "Russian",
        "English": "English",
        "Готово": "Done",
        "% массы тела — вес почти не мешает": "% of body mass — barely noticeable",
        "% массы тела — нормальная многодневка": "% of body mass — normal multi-day",
        "% массы тела — тяжело, риск растёт": "% of body mass — heavy, risk rising",
        "% массы тела — расход выше на треть": "% of body mass — +1/3 energy cost",
        "% массы тела — так ходить не надо": "% of body mass — don't hike like this",
        "+1 кг = +%d мин": "+1 kg = +%d min",
        "Профиль высот": "Elevation profile",
        "единица_км": "km",
        "единица_м": "m",
        "единица_кмч": "km/h",
        "Дальше": "Next",
        "Начать": "Start",
        "Пропустить": "Skip",
        "Обычные приложения делят расстояние на скорость": "Ordinary apps divide distance by speed",
        "Тропа к хижине Хёрнли под Маттерхорном. Справочное время — 2 часа.": "The trail to Hörnli hut below the Matterhorn. Published time: 2 hours.",
        "расстояние ÷ скорость": "distance ÷ speed",
        "с учётом рельефа": "terrain-aware",
        "Разница — почти втрое. Это и есть смысл приложения.": "Nearly a threefold difference. That is the whole point.",
        "Рюкзак меняет время сильнее, чем кажется": "Your pack changes the time more than you think",
        "Тот же маршрут. Подвигайте ползунок.": "Same route. Drag the slider.",
        "налегке": "no pack",
        "Сколько вы весите?": "What is your body weight?",
        "Пороги нагрузки считаются в процентах от массы тела. Можно пропустить.": "Load thresholds are a share of body mass. You can skip this.",
        "Как это работает": "How it works",
        "Слои": "Layers",
        "Отмывка рельефа": "Hillshade",
        "Спутник (онлайн)": "Satellite (online)",
        "Цвет по скорости": "Speed colors",
        "набор": "gain",
        "сброс": "loss",
        "средний темп": "avg pace",
        "без учёта рельефа": "flat estimate",
        "Нажмите ✎ и нарисуйте маршрут пальцем": "Tap ✎ and draw a route with your finger",
        "Один палец рисует, два — двигают карту": "One finger draws, two move the map",
        "Линия далеко от маршрута — начните у его конца": "Stroke too far from the route — start at its end",
        "Участок заменён новой линией": "Segment replaced with the new line",
        "Коснитесь линии — всё после этого места сотрётся": "Touch the line — everything past that point is erased",
    ]

    private var useEnglish: Bool {
        switch AppLanguage(rawValue: language) ?? .system {
        case .ru: return false
        case .en: return true
        case .system:
            return !(Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
        }
    }

    private static let ruUnits: [String: String] = [
        "единица_км": "км", "единица_м": "м", "единица_кмч": "км/ч",
    ]

    func t(_ key: String) -> String {
        if useEnglish { return Self.en[key] ?? key }
        return Self.ruUnits[key] ?? key
    }

    func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
