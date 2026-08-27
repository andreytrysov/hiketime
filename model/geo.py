"""Геометрия трека: расстояния, ресемплинг, сглаживание профиля."""
import math

R_EARTH = 6371008.8


def haversine(a, b):
    """Расстояние между (lat, lon) в метрах."""
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * R_EARTH * math.asin(math.sqrt(h))


def cumulative(points):
    out = [0.0]
    for i in range(1, len(points)):
        out.append(out[-1] + haversine(points[i - 1], points[i]))
    return out


def resample(points, step=25.0):
    """Точки через равные интервалы вдоль ломаной.

    Нужно, чтобы набор высоты не зависел от того, как густо записал GPS.
    """
    if len(points) < 2:
        return list(points)
    cum = cumulative(points)
    total = cum[-1]
    out, target, i = [points[0]], step, 1
    while target < total:
        while i < len(cum) - 1 and cum[i] < target:
            i += 1
        seg = cum[i] - cum[i - 1]
        t = 0.0 if seg == 0 else (target - cum[i - 1]) / seg
        lat = points[i - 1][0] + t * (points[i][0] - points[i - 1][0])
        lon = points[i - 1][1] + t * (points[i][1] - points[i - 1][1])
        out.append((lat, lon))
        target += step
    out.append(points[-1])
    return out


def smooth(values, window=5):
    """Скользящее среднее — глушит шум DEM и GPS, иначе набор высоты раздувается."""
    if window < 2 or len(values) < window:
        return list(values)
    half, out = window // 2, []
    for i in range(len(values)):
        lo, hi = max(0, i - half), min(len(values), i + half + 1)
        out.append(sum(values[lo:hi]) / (hi - lo))
    return out


def gain_loss(elevs, threshold=2.0):
    """Набор и сброс с порогом: изменения мельче порога считаем шумом."""
    gain = loss = 0.0
    ref = elevs[0]
    for e in elevs[1:]:
        d = e - ref
        if d > threshold:
            gain += d
            ref = e
        elif d < -threshold:
            loss += -d
            ref = e
    return gain, loss
