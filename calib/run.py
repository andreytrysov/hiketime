#!/usr/bin/env python3
"""Прогон калибровки: тропа из OSM -> профиль из DEM -> модели -> ошибка."""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from calib import router
from calib.routes import ROUTES, SOFT
from model.dem import DEM
from model import timemodel as tm
import route as route_mod

OUT = os.path.join(os.path.dirname(__file__), "results.json")


def main():
    dem = DEM(zoom=12)
    rows = []
    done = set()
    if os.path.exists(OUT):                      # возобновление после обрывов
        rows = json.load(open(OUT))
        done = {r["name"] for r in rows}
    todo = [(n, a, b, h, 5, 1.0, note, "clean") for n, a, b, h, note in ROUTES] + \
           [(n, a, b, h, kg, ter, note, "soft") for n, a, b, h, kg, ter, note in SOFT]
    for name, start, end, pub_h, load_kg, terrain, note, klass in todo:
        if name in done:
            print(f"-- {name}: уже есть")
            continue
        try:
            path = (router.route_via(start + [end]) if isinstance(start, list)
                    else router.route(start, end))
        except Exception as e:
            print(f"!! {name}: overpass не ответил ({e})")
            continue
        if not path or len(path) < 2:
            print(f"!! {name}: путь не найден")
            continue
        r = route_mod.build(path, dem=dem, step=25.0)
        e0, e1 = r["ele"][0], r["ele"][-1]
        rows.append({
            "name": name, "note": note, "pub_h": pub_h,
            "load_kg": load_kg, "terrain": terrain, "klass": klass,
            "dist_km": r["dist_m"]/1000, "gain": r["gain_m"], "loss": r["loss_m"],
            "segments": r["segments"],
        })
        print(f"ok {name}: {r['dist_m']/1000:.1f} км, +{r['gain_m']:.0f}/-{r['loss_m']:.0f}, "
              f"высоты {e0:.0f}->{e1:.0f}, норматив {pub_h:.2f} ч")
        json.dump(rows, open(OUT, "w"))          # сохраняем после каждого
    print(f"\nсохранено {len(rows)} маршрутов в {OUT}")


if __name__ == "__main__":
    main()
