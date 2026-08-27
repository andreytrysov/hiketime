"""Разбор GPX без внешних зависимостей."""
import xml.etree.ElementTree as ET
from datetime import datetime, timezone


def _text_time(s):
    s = s.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s).astimezone(timezone.utc)
    except ValueError:
        return None


def load(path):
    """-> dict: points [(lat,lon)], ele [м] или None, times [datetime] или None."""
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {"g": root.tag.split("}")[0].strip("{")} if "}" in root.tag else {}
    q = (lambda t: f"g:{t}") if ns else (lambda t: t)

    pts, eles, times = [], [], []
    nodes = root.findall(f".//{q('trkpt')}", ns) or root.findall(f".//{q('rtept')}", ns)
    for p in nodes:
        pts.append((float(p.get("lat")), float(p.get("lon"))))
        e = p.find(q("ele"), ns)
        eles.append(float(e.text) if e is not None and e.text else None)
        t = p.find(q("time"), ns)
        times.append(_text_time(t.text) if t is not None and t.text else None)

    return {
        "points": pts,
        "ele": eles if all(e is not None for e in eles) and eles else None,
        "times": times if all(t is not None for t in times) and times else None,
    }


def elapsed_hours(times):
    if not times:
        return None
    return (times[-1] - times[0]).total_seconds() / 3600.0


def moving_hours(times, points, stop_speed=0.3):
    """Время в движении: выбрасываем участки медленнее stop_speed м/с (привалы)."""
    from .geo import haversine
    if not times:
        return None
    total = 0.0
    for i in range(1, len(times)):
        dt = (times[i] - times[i - 1]).total_seconds()
        if dt <= 0:
            continue
        d = haversine(points[i - 1], points[i])
        if d / dt >= stop_speed:
            total += dt
    return total / 3600.0
