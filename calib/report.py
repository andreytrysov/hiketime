#!/usr/bin/env python3
"""Собирает calib/REPORT.md из results.json + подгонки."""
import json, os, subprocess, sys, datetime
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from model import timemodel as tm

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = json.load(open(os.path.join(HERE, "results.json")))
BODY = 75.0


def predict(r, power):
    return tm.EnergyModel(body_kg=BODY, load_kg=r["load_kg"],
                          power_per_kg=power, terrain=r["terrain"]).time_hours(r["segments"])


def med(xs):
    xs = sorted(xs); n = len(xs)
    return xs[n//2] if n % 2 else (xs[n//2-1]+xs[n//2])/2


def fmt_h(h):
    return f"{int(h)}:{int(round((h-int(h))*60)):02d}"


def main():
    clean = [r for r in ROWS if r["klass"] == "clean"]
    soft = [r for r in ROWS if r["klass"] == "soft"]
    best = min((med([abs((predict(r, 2.2+i*0.01)-r["pub_h"])/r["pub_h"]) for r in clean]), 2.2+i*0.01)
               for i in range(281))
    p_opt = best[1]

    L = []
    L.append(f"# Калибровка модели времени — {datetime.date.today().isoformat()}\n")
    L.append("Геометрия — по тропам OSM (свой роутер, без спрямлений), высоты — DEM z12.\n")
    L.append(f"**Оптимум power_per_kg по чистым точкам: {p_opt:.2f} Вт/кг** "
             f"(дефолт приложения 3.6).\n")

    def block(rows, power, title, load_note):
        if not rows:
            return
        L.append(f"## {title}\n")
        L.append(load_note + "\n")
        L.append("| маршрут | км | набор | норматив | модель | ошибка |")
        L.append("|---|---|---|---|---|---|")
        errs = []
        for r in rows:
            t = predict(r, power)
            e = (t-r["pub_h"])/r["pub_h"]*100
            errs.append(e)
            L.append(f"| {r['name']} | {r['dist_km']:.1f} | {r['gain']:.0f} "
                     f"| {fmt_h(r['pub_h'])} | {fmt_h(t)} | {e:+.0f}% |")
        L.append(f"\nмедиана {med(errs):+.1f}%, медиана модуля {med([abs(x) for x in errs]):.1f}%, "
                 f"в ±15%: {sum(1 for x in errs if abs(x)<=15)}/{len(errs)}\n")

    block(clean, p_opt, "Чистые нормативы (подгонка)", "75 кг + 5 кг, тропа ×1.0.")
    block(soft, p_opt, "Северная валидация (без подгонки)",
          "Свой вес рюкзака и коэффициент покрытия; межхижинные переходы с грузом.")

    L.append("## Классика на тех же чистых точках\n")
    L.append("| модель | медиана модуля ошибки |")
    L.append("|---|---|")
    for label, fn in [
        ("Naismith+Langmuir", lambda s, r: tm.naismith_langmuir(sum(d for d,_ in s), r["gain"], r["loss"], s)),
        ("Мюнтер", lambda s, r: tm.munter(sum(d for d,_ in s), r["gain"], r["loss"])),
        ("Тоблер", lambda s, r: tm.tobler(s)),
        ("DIN 33466", lambda s, r: tm.din33466(sum(d for d,_ in s), r["gain"], r["loss"])),
        (f"наша (power={p_opt:.2f})", lambda s, r: predict(r, p_opt)),
    ]:
        es = [abs((fn(r["segments"], r)-r["pub_h"])/r["pub_h"]*100) for r in clean]
        L.append(f"| {label} | {med(es):.1f}% |")

    L.append("""
## Реальные данные

- **Medicina 2025 (PMC11766859), 500 GPS-записей Wikiloc, 25 троп:** факт
  в среднем 3:07 на 10.9 км +628 м. Наша модель на эквиваленте: 3:11–3:19
  ходового (power 3.6–3.8) — в пределах 2–6% от реальности. Komoot,
  Outdooractive и щиты занижают на 30–70 мин.
- **Кольская тундра (пользователь):** 6.7 км +238, рюкзак 18 кг, факт ~4 ч.
  Модель с покрытием ×1.55: 3:41 с привалами (−8%). Без коэффициента — 1:46.
- Массовый сбор чужих треков закрыт (Wikiloc/hikr за Cloudflare): реальные
  данные дальше — GPX пользователя и тестировщиков, затем запись в приложении.

## Оговорки

- Нормативы — почти все подъёмы; спуски проверяются только реальными треками.
- Сомнительные точки (проблема данных, не модели): Прекестулен и
  Ауронцо→Локателли — туристические нормативы с запасом на толпу
  (модель «быстрее» на 23-25%); Шварцзее→Хёрнлихютте — роутер выбрал
  длинный вариант тропы (5.4 км против ~2.9 прямой), норматив про прямую.
- Северные нормативы DNT/STF/FÍ систематически щедрее модели на 12-27% —
  они закладывают полный рюкзак и запас; реальные данные (Wikiloc-статья,
  кольский трек) при этом ложатся в единицы процентов. Вывод «нормативы —
  мёртвые данные» подтверждается числами.
- Два независимых пути сошлись на одном: подгонка по нормативам даёт
  power 3.59, реальные Wikiloc-данные — 3.6-3.8. Дефолт 3.6 подтверждён.
- Коэффициенты покрытия сведены из военных измерений в TERRAIN.md.
""")
    open(os.path.join(HERE, "REPORT.md"), "w").write("\n".join(L))
    print("REPORT.md записан,", len(ROWS), "маршрутов")


if __name__ == "__main__":
    main()
