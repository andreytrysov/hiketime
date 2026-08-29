#!/usr/bin/env python3
"""mbtiles -> дерево z/x/y.pbf, которое MapLibre читает по file://

Planetiler кладёт тайлы в SQLite в схеме TMS (ось Y снизу), а MapLibre
ждёт XYZ (сверху) — при распаковке переворачиваем. Гзип не трогаем:
MapLibre узнаёт его по сигнатуре и распаковывает сам.
"""
import argparse, os, sqlite3, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mbtiles")
    ap.add_argument("outdir")
    a = ap.parse_args()

    db = sqlite3.connect(a.mbtiles)
    meta = dict(db.execute("select name, value from metadata"))
    print("формат:", meta.get("format"), "| зумы:",
          meta.get("minzoom"), "-", meta.get("maxzoom"))

    n = 0
    total = 0
    for z, x, y_tms, data in db.execute(
            "select zoom_level, tile_column, tile_row, tile_data from tiles"):
        y = (1 << z) - 1 - y_tms          # TMS -> XYZ
        d = os.path.join(a.outdir, str(z), str(x))
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f"{y}.pbf")
        with open(path, "wb") as f:
            f.write(data)
        n += 1
        total += len(data)
    print(f"распаковано {n} тайлов, {total/1e6:.1f} МБ в {a.outdir}")


if __name__ == "__main__":
    main()
