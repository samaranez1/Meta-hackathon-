#!/usr/bin/env python3
"""Maintained regression tests for ai/server.py (stdlib unittest only).

Run:  python3 ai/test_server.py
"""
import json
import os
import socket
import sys
import threading
import time
import unittest
import urllib.request
from contextlib import redirect_stderr
from http.server import ThreadingHTTPServer
from io import StringIO

# Import the server with no Meta key so chat() never touches the network.
for _k in ("META_API_KEY", "META_MODEL_API_KEY"):
    os.environ.pop(_k, None)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server as wingman  # noqa: E402

wingman.META_API_KEY = ""


def _post(base, path, payload):
    req = urllib.request.Request(
        base + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.status, json.loads(r.read().decode())


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), wingman.Handler)
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever,
                                      kwargs={"poll_interval": 0.05},
                                      daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=10)

    def test_health(self):
        with urllib.request.urlopen(self.base + "/health", timeout=10) as r:
            d = json.loads(r.read().decode())
        self.assertTrue(d["ok"])
        self.assertFalse(d["meta_configured"])

    def test_briefing_fallback_shape(self):
        status, d = _post(self.base, "/briefing",
                          {"level": 3, "level_name": "CHROMA STORM",
                           "hp_pct": 60, "kills": 25})
        self.assertEqual(status, 200)
        for key in ("briefing", "taunt", "tip"):
            self.assertTrue(d[key], key)
        self.assertEqual(d["source"], "fallback")

    def test_director_bounds_and_rules(self):
        status, d = _post(self.base, "/director",
                          {"level": 3, "hp_frac": 0.2,
                           "kills_per_min": 4.0, "deaths": 1})
        self.assertEqual(status, 200)
        self.assertGreaterEqual(d["spawn_interval_mult"], 0.8)
        self.assertLessEqual(d["spawn_interval_mult"], 1.4)
        self.assertGreaterEqual(d["enemy_scale_mult"], 0.8)
        self.assertLessEqual(d["enemy_scale_mult"], 1.2)
        # Struggling pilot: rules ease off.
        self.assertGreater(d["spawn_interval_mult"], 1.0)
        self.assertLess(d["enemy_scale_mult"], 1.0)

    def test_coach_shape(self):
        status, d = _post(self.base, "/coach",
                          {"score": 9000, "kills": 40, "level_reached": 3,
                           "deaths": 1, "victory": False})
        self.assertEqual(status, 200)
        self.assertTrue(d["advice"])

    def test_client_disconnect_is_quiet(self):
        """Regression: a client that hangs up mid-response must not traceback,
        and the server must keep serving (see BrokenPipeError report)."""
        real_chat = wingman.chat
        wingman.chat = lambda *a, **k: (time.sleep(2), None)[1]
        self.addCleanup(setattr, wingman, "chat", real_chat)
        body = json.dumps({"score": 1, "kills": 1, "level_reached": 1,
                           "deaths": 0, "victory": False}).encode()
        raw = (b"POST /coach HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
               b"Content-Length: %d\r\nConnection: close\r\n\r\n" % len(body)) + body
        buf = StringIO()
        with redirect_stderr(buf):
            s = socket.create_connection(
                ("127.0.0.1", self.server.server_address[1]), timeout=10)
            s.sendall(raw)
            s.close()  # hang up before the slow handler answers
            time.sleep(4)  # let the handler finish into the dead socket
        log = buf.getvalue()
        self.assertNotIn("Traceback", log)
        self.assertNotIn("BrokenPipeError", log)
        # Server still alive.
        with urllib.request.urlopen(self.base + "/health", timeout=10) as r:
            self.assertEqual(r.status, 200)


if __name__ == "__main__":
    unittest.main(verbosity=2)
