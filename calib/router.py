"""Маршрут по реальным тропам из OSM.

Тянем пешеходный граф в прямоугольнике вокруг старта и финиша через
Overpass, строим кратчайший путь Дейкстрой. Это даёт честную геометрию
с серпантинами — рисованные от руки точки спрямляют тропу и занижают
дистанцию, на этом мы уже обжигались.
"""
import heapq, json, math, os, ssl, time, urllib.parse, urllib.request
import certifi

CACHE = os.path.join(os.path.dirname(__file__), "overpass_cache")
API = "https://overpass-api.de/api/interpreter"
FOOT = "path|footway|track|steps|bridleway|unclassified|residential|service|pedestrian|living_street"


def _fetch(query):
    os.makedirs(CACHE, exist_ok=True)
    key = os.path.join(CACHE, f"{abs(hash(query))}.json")
    if os.path.exists(key):
        return json.load(open(key))
    ctx = ssl.create_default_context(cafile=certifi.where())
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(3):
        try:
            with urllib.request.urlopen(API, data=data, timeout=180, context=ctx) as r:
                out = json.load(r)
            json.dump(out, open(key, "w"))
            return out
        except Exception:
            if attempt == 2:
                raise
            time.sleep(20)


def haversine(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((la2-la1)/2)**2
         + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2)
    return 2*6371008.8*math.asin(math.sqrt(h))


def route(start, end, pad=0.02):
    """(lat,lon) -> (lat,lon): список (lat,lon) вдоль троп или None."""
    s, n = min(start[0], end[0])-pad, max(start[0], end[0])+pad
    w, e = min(start[1], end[1])-pad, max(start[1], end[1])+pad
    q = (f'[out:json][timeout:170];way({s},{w},{n},{e})'
         f'["highway"~"^({FOOT})$"];(._;>;);out;')
    data = _fetch(q)

    nodes, adj = {}, {}
    for el in data["elements"]:
        if el["type"] == "node":
            nodes[el["id"]] = (el["lat"], el["lon"])
    for el in data["elements"]:
        if el["type"] != "way":
            continue
        ids = [i for i in el["nodes"] if i in nodes]
        for a, b in zip(ids, ids[1:]):
            d = haversine(nodes[a], nodes[b])
            adj.setdefault(a, []).append((b, d))
            adj.setdefault(b, []).append((a, d))
    if not adj:
        return None

    def nearest(pt):
        return min(adj, key=lambda i: haversine(nodes[i], pt))

    src, dst = nearest(start), nearest(end)
    dist = {src: 0.0}
    prev = {}
    pq = [(0.0, src)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == dst:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w_ in adj[u]:
            nd = d + w_
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = u
                heapq.heappush(pq, (nd, v))
    if dst not in dist:
        return None

    path, cur = [], dst
    while cur != src:
        path.append(nodes[cur])
        cur = prev[cur]
    path.append(nodes[src])
    path.reverse()
    # хвосты от точек привязки до реальных старта/финиша не добавляем:
    # старт обычно и есть узел тропы, а ошибка привязки — десятки метров
    return path
