"""Высоты из тайлов terrarium (AWS Open Data, public domain).

Тайл — PNG, высота закодирована в пикселе: (R*256 + G + B/256) - 32768.
Те же тайлы пойдут в приложение: они дают и рельеф для модели, и отмывку на карте.
"""
import io, math, os, ssl, urllib.request
import certifi
from PIL import Image
import numpy as np

TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
CACHE = os.path.join(os.path.dirname(__file__), "..", "cache")


def _deg2px(lat, lon, z):
    """Географические координаты -> глобальные пиксели тайловой сетки."""
    n = 2.0 ** z * 256
    x = (lon + 180.0) / 360.0 * n
    s = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n
    return x, y


class DEM:
    def __init__(self, zoom=12):
        self.zoom = zoom
        self._tiles = {}
        os.makedirs(CACHE, exist_ok=True)

    def _tile(self, tx, ty):
        key = (tx, ty)
        if key in self._tiles:
            return self._tiles[key]
        path = os.path.join(CACHE, f"terrarium_{self.zoom}_{tx}_{ty}.png")
        if not os.path.exists(path):
            url = TILE_URL.format(z=self.zoom, x=tx, y=ty)
            ctx = ssl.create_default_context(cafile=certifi.where())
            with urllib.request.urlopen(url, timeout=30, context=ctx) as r:
                data = r.read()
            with open(path, "wb") as f:
                f.write(data)
        img = Image.open(path).convert("RGB")
        a = np.asarray(img, dtype=np.float64)
        elev = a[:, :, 0] * 256.0 + a[:, :, 1] + a[:, :, 2] / 256.0 - 32768.0
        self._tiles[key] = elev
        return elev

    def elevation(self, lat, lon):
        """Билинейная интерполяция высоты в метрах."""
        px, py = _deg2px(lat, lon, self.zoom)
        # центр пикселя смещён на полпикселя
        fx, fy = px - 0.5, py - 0.5
        x0, y0 = math.floor(fx), math.floor(fy)
        dx, dy = fx - x0, fy - y0
        vals = {}
        for oy in (0, 1):
            for ox in (0, 1):
                gx, gy = x0 + ox, y0 + oy
                tx, ty = gx // 256, gy // 256
                t = self._tile(int(tx), int(ty))
                vals[(ox, oy)] = t[int(gy % 256), int(gx % 256)]
        top = vals[(0, 0)] * (1 - dx) + vals[(1, 0)] * dx
        bot = vals[(0, 1)] * (1 - dx) + vals[(1, 1)] * dx
        return top * (1 - dy) + bot * dy

    def profile(self, points):
        return [self.elevation(lat, lon) for lat, lon in points]
