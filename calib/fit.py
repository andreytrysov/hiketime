#!/usr/bin/env python3
"""Подгонка по нормативам и валидация по «мягким» северным точкам.

Свободный параметр — power_per_kg. Чистые точки: 75 кг + 5 кг, тропа.
Мягкие: свой вес рюкзака и коэффициент покрытия из routes.py.
"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from model import timemodel as tm

ROWS = json.load(open(os.path.join(os.path.dirname(__file__), "results.json")))
BODY = 75.0


def predict(r, power):
    m = tm.EnergyModel(body_kg=BODY, load_kg=r["load_kg"],
                       power_per_kg=power, terrain=r["terrain"])
    return m.time_hours(r["segments"])


def med(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n//2] if n % 2 else (xs[n//2-1] + xs[n//2]) / 2


def table(rows, power, title):
    print(f"\n{title}")
    print(f"{'маршрут':<34}{'км':>6}{'набор':>7}{'норматив':>9}{'модель':>8}{'ошибка':>8}")
    errs = []
    for r in rows:
        t = predict(r, power)
        e = (t - r["pub_h"]) / r["pub_h"] * 100
        errs.append(e)
        print(f"{r['name']:<34}{r['dist_km']:>6.1f}{r['gain']:>7.0f}"
              f"{r['pub_h']:>9.2f}{t:>8.2f}{e:>+7.1f}%")
    if errs:
        print(f"  медиана {med(errs):+.1f}%, |медиана| {med([abs(x) for x in errs]):.1f}%, "
              f"в ±15%: {sum(1 for x in errs if abs(x) <= 15)}/{len(errs)}")
    return errs


def main():
    clean = [r for r in ROWS if r["klass"] == "clean"]
    soft = [r for r in ROWS if r["klass"] == "soft"]

    best = None
    for i in range(281):
        p = 2.2 + i * 0.01
        score = med([abs((predict(r, p) - r["pub_h"]) / r["pub_h"]) for r in clean])
        if best is None or score < best[1]:
            best = (p, score)
    p_opt = best[0]
    print(f"оптимум по чистым точкам: power_per_kg = {p_opt:.2f} Вт/кг")

    table(clean, p_opt, f"ЧИСТЫЕ НОРМАТИВЫ (подгонка), power={p_opt:.2f}")
    table(soft, p_opt, "СЕВЕРНАЯ ВАЛИДАЦИЯ (свой вес и покрытие, без подгонки)")
    table(clean, 3.6, "СПРАВОЧНО: чистые на текущем дефолте power=3.6")

    print("\nклассика на чистых точках:")
    for label, fn in [
        ("Naismith+Langmuir", lambda s, r: tm.naismith_langmuir(
            sum(d for d, _ in s), r["gain"], r["loss"], s)),
        ("Мюнтер", lambda s, r: tm.munter(sum(d for d, _ in s), r["gain"], r["loss"])),
        ("Тоблер", lambda s, r: tm.tobler(s)),
        ("DIN 33466", lambda s, r: tm.din33466(sum(d for d, _ in s), r["gain"], r["loss"])),
    ]:
        es = [abs((fn(r["segments"], r) - r["pub_h"]) / r["pub_h"] * 100) for r in clean]
        print(f"  {label:<20} |медиана| {med(es):.1f}%")


if __name__ == "__main__":
    main()
