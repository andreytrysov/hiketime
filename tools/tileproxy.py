#!/usr/bin/env python3
"""Прокси тайлов для разработки.

Симулятор не резолвит внешние имена, когда на маке поднят VPN: DNS уходит
в туннель и не возвращается. Сам мак при этом ходит в сеть нормально.
Этот прокси слушает localhost (его резолвить не надо) и переливает тайлы.

    ./.venv/bin/python tools/tileproxy.py

Включить в приложении (только для отладки):
    xcrun simctl spawn booted defaults write com.andreytrusov.hiketime \
        tileProxyBase -string "http://localhost:8790"
"""
import http.server, socketserver, ssl, urllib.request
import certifi

PORT = 8790
UPSTREAM = {
    "terrarium": "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{rest}",
    "otm":       "https://tile.opentopomap.org/{rest}",
    "osm":       "https://tile.openstreetmap.org/{rest}",
    "sat":       "https://server.arcgisonline.com/ArcGIS/rest/services/"
                 "World_Imagery/MapServer/tile/{rest}",
}
CTX = ssl.create_default_context(cafile=certifi.where())


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        parts = self.path.lstrip("/").split("/", 1)
        if len(parts) != 2 or parts[0] not in UPSTREAM:
            self.send_error(404, "unknown source")
            return
        url = UPSTREAM[parts[0]].format(rest=parts[1])
        req = urllib.request.Request(url, headers={
            "User-Agent": "hiketime-dev-proxy/0.1 (andreytrysov@gmail.com)"})
        try:
            with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
                data = r.read()
                ctype = r.headers.get("Content-Type", "image/png")
        except Exception as e:
            self.send_error(502, str(e))
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print(f"прокси тайлов: http://localhost:{PORT}")
    Server(("127.0.0.1", PORT), Handler).serve_forever()
