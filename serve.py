#!/usr/bin/env python3
"""Статика + высоты. Браузеру нельзя читать пиксели чужих тайлов (нет CORS),
поэтому высоты отдаёт этот эндпоинт — тем же кодом, что и первый прототип."""
import json, os
from http.server import HTTPServer, SimpleHTTPRequestHandler
from model.dem import DEM

DEM_ = DEM(zoom=12)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs")


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def log_message(self, *a):
        pass

    def do_POST(self):
        if self.path != "/elev":
            return self.send_error(404)
        n = int(self.headers.get("Content-Length", 0))
        pts = json.loads(self.rfile.read(n))
        try:
            out = [round(DEM_.elevation(la, lo), 1) for la, lo in pts]
        except Exception as e:
            return self.send_error(500, str(e))
        body = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    import socket
    s_ = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s_.connect(("8.8.8.8", 80)); ip = s_.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s_.close()
    print(f"  на этом маке: http://localhost:8770")
    print(f"  с телефона:   http://{ip}:8770")
    HTTPServer(("0.0.0.0", 8770), H).serve_forever()
