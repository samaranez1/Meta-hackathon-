"""Vercel serverless: POST /api/director"""
from http.server import BaseHTTPRequestHandler
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ai.wingman_core import make_director  # noqa: E402
import _common as common  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        common.send_options(self)

    def _run(self, payload):
        if not common.guard(self):
            return
        try:
            common.serve_result(self, make_director(payload))
        except Exception as e:
            common.send_json(self, 500, {"ok": False, "error": str(e)[:200]})

    def do_POST(self):
        self._run(common.read_json(self))

    def do_GET(self):
        self._run({})

    def log_message(self, *a):
        pass
