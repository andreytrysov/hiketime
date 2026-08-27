#!/usr/bin/env python3
"""Сравнение моделей времени на треке.

  ./predict.py трек.gpx --load 12 --body 75 [--actual 4.5]
  ./predict.py --wpt "46.0,7.7;46.01,7.71" --load 12
"""
import argparse, json, os, sys
from model import gpx, timemodel as tm
from model.dem import DEM
import route as route_mod


def fmt_h(h):
    return f"{int(h)}:{int(round((h - int(h)) * 60)):02d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gpx", nargs="?")
    ap.add_argument("--wpt", help="точки 'lat,lon;lat,lon;...' вместо файла")
    ap.add_argument("--load", type=float, default=0.0, help="вес рюкзака, кг")
    ap.add_argument("--body", type=float, default=75.0, help="вес человека, кг")
    ap.add_argument("--power", type=float, default=3.6, help="Вт/кг, посильная мощность")
    ap.add_argument("--terrain", type=float, default=1.0, help="множитель сложности покрытия")
    ap.add_argument("--actual", type=float, help="фактическое время в часах")
    ap.add_argument("--zoom", type=int, default=12)
    ap.add_argument("--step", type=float, default=25.0)
    a = ap.parse_args()

    if a.wpt:
        pts = [tuple(float(v) for v in p.split(",")) for p in a.wpt.split(";")]
        name = "маршрут по точкам"
        actual = a.actual
    elif a.gpx:
        g = gpx.load(a.gpx)
        pts = g["points"]
        name = os.path.basename(a.gpx)
        actual = a.actual or gpx.moving_hours(g["times"], g["points"])
        meta = os.path.splitext(a.gpx)[0] + ".json"
        if os.path.exists(meta):
            m = json.load(open(meta))
            a.load = m.get("load_kg", a.load)
            a.body = m.get("body_kg", a.body)
            actual = a.actual or m.get("actual_hours") or actual
    else:
        ap.error("нужен GPX или --wpt")

    r = route_mod.build(pts, dem=DEM(zoom=a.zoom), step=a.step)
    segs = r["segments"]

    print(f"\n{name}")
    print(f"  точек после ресемплинга {len(r['points'])} через {a.step:.0f} м")
    print(f"  расстояние {r['dist_m']/1000:.2f} км   "
          f"набор {r['gain_m']:.0f} м   сброс {r['loss_m']:.0f} м")
    print(f"  высоты {r['ele_min']:.0f}..{r['ele_max']:.0f} м")
    print(f"  рюкзак {a.load:.0f} кг, человек {a.body:.0f} кг\n")

    energy = tm.EnergyModel(body_kg=a.body, load_kg=a.load,
                            power_per_kg=a.power, terrain=a.terrain)
    results = [
        ("наивно (÷4 км/ч)", tm.naive_hours(r["dist_m"])),
        ("Naismith+Langmuir", tm.naismith_langmuir(r["dist_m"], r["gain_m"], r["loss_m"], segs)),
        ("DIN 33466", tm.din33466(r["dist_m"], r["gain_m"], r["loss_m"])),
        ("Мюнтер", tm.munter(r["dist_m"], r["gain_m"], r["loss_m"])),
        ("Тоблер", tm.tobler(segs)),
        ("энергетическая", energy.time_hours(segs)),
    ]

    for label, h in results:
        line = f"  {label:<20} {fmt_h(h):>6}"
        if actual:
            err = (h - actual) / actual * 100
            line += f"   {err:+6.1f}%"
        print(line)

    if actual:
        print(f"\n  {'факт':<20} {fmt_h(actual):>6}")

    # чувствительность к весу — та самая строчка «+1 кг = +N мин»
    base = energy.time_hours(segs)
    plus = tm.EnergyModel(body_kg=a.body, load_kg=a.load + 1,
                          power_per_kg=a.power, terrain=a.terrain).time_hours(segs)
    print(f"\n  каждый лишний кг: +{(plus - base) * 60:.0f} мин")
    print(f"  нагрузка: {a.load / a.body * 100:.0f}% от массы тела\n")


if __name__ == "__main__":
    main()
