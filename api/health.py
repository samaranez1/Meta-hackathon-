"""Vercel serverless: GET /api/health"""
from http.server import BaseHTTPRequestHandler
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ai.wingman_core import health_payload  # noqa: E402
import _common as common  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        common.send_options(self)

    def _run(self):
        if not common.guard(self):
            return
        # Health is a status probe: always 200, meta_configured tells
        # the story. Content endpoints 503 when only fallback exists.
        common.send_json(self, 200, health_payload())

    def do_GET(self):
        self._run()

    def do_POST(self):
        self._run()

    def log_message(self, *a):
        pass
