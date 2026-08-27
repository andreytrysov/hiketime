#!/usr/bin/env python3
"""Подгонка модели по нормативным временам.

Свободный параметр — power_per_kg (посильная мощность). Норматив считаем
временем в движении лёгкого ходока: рюкзак 5 кг, человек 75 кг.
Перекос выборки: почти все нормативы — подъёмы; спуски проверяем той же
кривой Minetti без отдельной подгонки.
"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from model import timemodel as tm

ROWS = json.load(open(os.path.join(os.path.dirname(__file__), "results.json")))
BODY, LOAD = 75.0, 5.0


def predict(segs, power):
    return tm.EnergyModel(body_kg=BODY, load_kg=LOAD, power_per_kg=power).time_hours(segs)


def errors(power):
    out = []
    for r in ROWS:
        t = predict(r["segments"], power)
        out.append((r, t, (t - r["pub_h"]) / r["pub_h"] * 100))
    return out


def med(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n//2] if n % 2 else (xs[n//2-1] + xs[n//2]) / 2


def main():
    best = None
    for i in range(281):
        p = 2.2 + i * 0.01
        e = [abs(x[2]) for x in errors(p)]
        score = med(e)
        if best is None or score < best[1]:
            best = (p, score)
    p_opt = best[0]

    print(f"оптимум power_per_kg = {p_opt:.2f} Вт/кг (медианная |ошибка| {best[1]:.1f}%)\n")
    print(f"{'маршрут':<32}{'км':>6}{'набор':>7}{'норматив':>9}{'модель':>8}{'ошибка':>8}")
    errs = []
    for r, t, e in errors(p_opt):
        errs.append(e)
        print(f"{r['name']:<32}{r['dist_km']:>6.1f}{r['gain']:>7.0f}"
              f"{r['pub_h']:>9.2f}{t:>8.2f}{e:>+7.1f}%")
    inside = sum(1 for e in errs if abs(e) <= 15)
    print(f"\nв пределах ±15%: {inside} из {len(errs)}")
    print(f"медиана ошибки {med(errs):+.1f}%, медиана |ошибки| {med([abs(e) for e in errs]):.1f}%")

    # сравнение с классикой на тех же данных
    for label, fn in [
        ("Naismith+Langmuir", lambda s, r: tm.naismith_langmuir(
            sum(d for d, _ in s), r["gain"], r["loss"], s)),
        ("Мюнтер", lambda s, r: tm.munter(sum(d for d, _ in s), r["gain"], r["loss"])),
        ("Тоблер", lambda s, r: tm.tobler(s)),
    ]:
        es = [abs((fn(r["segments"], r) - r["pub_h"]) / r["pub_h"] * 100) for r in ROWS]
        print(f"{label:<20} медиана |ошибки| {med(es):.1f}%")


if __name__ == "__main__":
    main()
