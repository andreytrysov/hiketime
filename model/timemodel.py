"""Модели времени прохождения.

Классические правила (Naismith, DIN, Munter, Tobler) — как опора для сравнения.
Наш кандидат — энергетический: считаем стоимость метра пути по уклону,
задаём посильную мощность, из неё получаем скорость. Вес входит физически,
а не отдельным штрафом сверху.
"""
import math

MAX_SPEED = 6.0 / 3.6      # м/с, быстрее пешком по тропе не ходят
MIN_SPEED = 0.15           # м/с, ниже — уже не ходьба


# ---------- классические правила ----------

def naismith_langmuir(dist_m, gain_m, loss_m, segments=None, flat_kmh=5.0):
    """Naismith: 5 км/ч + 1 час на 600 м набора. Поправки Лангмура на спуск."""
    h = dist_m / 1000.0 / flat_kmh + gain_m / 600.0
    if segments:
        for d, dh in segments:
            if dh >= 0 or d <= 0:
                continue
            angle = math.degrees(math.atan(abs(dh) / d))
            if 5 <= angle <= 12:
                h -= (abs(dh) / 300.0) * (10 / 60.0)   # пологий спуск ускоряет
            elif angle > 12:
                h += (abs(dh) / 300.0) * (10 / 60.0)   # крутой спуск тормозит
    return max(h, 0.0)


def din33466(dist_m, gain_m, loss_m, flat_kmh=4.0, up_mh=300.0, down_mh=500.0):
    """DIN 33466: большее из горизонтального и вертикального плюс половина меньшего."""
    horiz = dist_m / 1000.0 / flat_kmh
    vert = gain_m / up_mh + loss_m / down_mh
    return max(horiz, vert) + min(horiz, vert) / 2.0


def munter(dist_m, gain_m, loss_m, up_rate=4.0, flat_rate=6.0, down_rate=10.0):
    """Метод Мюнтера: единицы = км + метры набора/100, делим на темп."""
    km = dist_m / 1000.0
    t = 0.0
    if gain_m > 0:
        t += (km * gain_m / max(gain_m + loss_m, 1e-9) + gain_m / 100.0) / up_rate
    if loss_m > 0:
        t += (km * loss_m / max(gain_m + loss_m, 1e-9) + loss_m / 100.0) / down_rate
    if gain_m + loss_m == 0:
        t = km / flat_rate
    return t


def tobler(segments):
    """Функция Тоблера: скорость от уклона. Про вес не знает вовсе."""
    t = 0.0
    for d, dh in segments:
        if d <= 0:
            continue
        s = dh / d
        kmh = 6.0 * math.exp(-3.5 * abs(s + 0.05))
        t += (d / 1000.0) / max(kmh, 0.3)
    return t


# ---------- энергетическая модель ----------

def minetti_cost(i):
    """Стоимость метра пути, Дж/(кг·м), по уклону i = dh/dx.

    Minetti et al. 2002. Минимум около i = -0.10: пологий спуск дешевле ровного.
    За пределами +-0.45 полином расходится, поэтому зажимаем.
    """
    i = max(-0.45, min(0.45, i))
    c = (280.5 * i**5 - 58.7 * i**4 - 76.8 * i**3
         + 51.9 * i**2 + 19.6 * i + 2.5)
    return max(c, 0.4)


class EnergyModel:
    """Скорость из посильной мощности.

    power_per_kg  — сколько ватт на кг массы тела человек держит часами (форма)
    load_factor   — во сколько раз килограмм груза дороже килограмма своего тела
    terrain       — множитель стоимости: тропа 1.0, осыпь/болото больше
    """

    def __init__(self, body_kg=75.0, load_kg=0.0,
                 power_per_kg=3.6, load_factor=1.15, terrain=1.0,
                 load_penalty_k=0.0):
        self.body_kg = body_kg
        self.load_kg = load_kg
        self.power_per_kg = power_per_kg
        self.load_factor = load_factor
        self.terrain = terrain
        # Нелинейная надбавка за тяжёлый рюкзак, по образцу члена (L/W)^2 у Пандольфа.
        # По умолчанию 0: подбирать только по реальным трекам, иначе это выдуманное число.
        self.load_penalty_k = load_penalty_k

    @property
    def effective_kg(self):
        return self.body_kg + self.load_kg * self.load_factor

    @property
    def power_w(self):
        # мощность даёт тело, поэтому она от своей массы, а не от общей
        return self.power_per_kg * self.body_kg

    def speed(self, slope):
        rel = self.load_kg / self.body_kg
        cost = minetti_cost(slope) * self.terrain * (1.0 + self.load_penalty_k * rel ** 2)
        v = self.power_w / (cost * self.effective_kg)  # м/с
        return max(MIN_SPEED, min(MAX_SPEED, v))

    def time_hours(self, segments):
        t = 0.0
        for d, dh in segments:
            if d <= 0:
                continue
            t += d / self.speed(dh / d)
        return t / 3600.0


def naive_hours(dist_m, kmh=4.0):
    """То, что показывают обычные приложения: расстояние делить на скорость."""
    return dist_m / 1000.0 / kmh
