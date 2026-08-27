#!/usr/bin/env python3
"""Прогон калибровки: тропа из OSM -> профиль из DEM -> модели -> ошибка."""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from calib import router
from calib.routes import ROUTES
from model.dem import DEM
from model import timemodel as tm
import route as route_mod

OUT = os.path.join(os.path.dirname(__file__), "results.json")


def main():
    dem = DEM(zoom=12)
    rows = []
    for name, start, end, pub_h, note in ROUTES:
        try:
            path = router.route(start, end)
        except Exception as e:
            print(f"!! {name}: overpass не ответил ({e})")
            continue
        if not path or len(path) < 2:
            print(f"!! {name}: путь не найден")
            continue
        r = route_mod.build(path, dem=dem, step=25.0)
        rows.append({
            "name": name, "note": note, "pub_h": pub_h,
            "dist_km": r["dist_m"]/1000, "gain": r["gain_m"], "loss": r["loss_m"],
            "segments": r["segments"],
        })
        print(f"ok {name}: {r['dist_m']/1000:.1f} км, +{r['gain_m']:.0f}/-{r['loss_m']:.0f}, норматив {pub_h:.2f} ч")
    json.dump(rows, open(OUT, "w"))
    print(f"\nсохранено {len(rows)} маршрутов в {OUT}")


if __name__ == "__main__":
    main()
