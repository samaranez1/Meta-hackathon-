"""Vercel serverless: POST /api/director"""
from http.server import BaseHTTPRequestHandler
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from ai.wingman_core import make_director  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(raw)

    def _payload(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0:
                return {}
            data = json.loads(self.rfile.read(length).decode() or "{}")
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        try:
            self._send(200, make_director(self._payload()))
        except Exception as e:
            self._send(500, {"ok": False, "error": str(e)[:200]})

    def do_GET(self):
        try:
            self._send(200, make_director({}))
        except Exception as e:
            self._send(500, {"ok": False, "error": str(e)[:200]})

    def log_message(self, *a):
        pass
