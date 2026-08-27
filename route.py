"""Трек -> профиль -> сегменты. Общая подготовка данных для всех моделей."""
from model import geo
from model.dem import DEM


def build(points, dem=None, step=25.0, smooth_window=5, threshold=2.0):
    dem = dem or DEM()
    pts = geo.resample(points, step=step)
    raw = dem.profile(pts)
    ele = geo.smooth(raw, window=smooth_window)

    segments = []
    for i in range(1, len(pts)):
        d = geo.haversine(pts[i - 1], pts[i])
        segments.append((d, ele[i] - ele[i - 1]))

    gain, loss = geo.gain_loss(ele, threshold=threshold)
    return {
        "points": pts,
        "ele": ele,
        "segments": segments,
        "dist_m": sum(d for d, _ in segments),
        "gain_m": gain,
        "loss_m": loss,
        "ele_min": min(ele),
        "ele_max": max(ele),
    }
