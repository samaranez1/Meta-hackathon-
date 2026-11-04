#!/usr/bin/env python3
"""Maintained regression tests for api/*.py Vercel functions (stdlib only).

Run:  python3 ai/test_api.py

Exercises the real handler classes over localhost HTTP: exact response
shapes, 503-when-fallback policy, rate limiting, CORS, input sanitizing.
No Meta key is configured here, so live-AI shapes use a stubbed chat().
"""
import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

# No Meta key: chat() must never touch the network unless stubbed.
for _k in ("META_API_KEY", "META_MODEL_API_KEY"):
    os.environ.pop(_k, None)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "api"))
import _common as common  # noqa: E402
import ai.wingman_core as core  # noqa: E402
from briefing import handler as BriefingHandler  # noqa: E402
from coach import handler as CoachHandler  # noqa: E402
from director import handler as DirectorHandler  # noqa: E402
from health import handler as HealthHandler  # noqa: E402


def _call(base, path, payload=None, method="POST", raw=None, headers=None):
    data = raw
    if data is None and payload is not None:
        data = json.dumps(payload).encode()
    req = urllib.request.Request(
        base + path, data=data,
        headers={"Content-Type": "application/json", **(headers or {})},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode(), dict(r.headers)
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read().decode(), dict(e.headers)
        finally:
            e.close()


def _fake_chat(text):
    def _chat(system, user, max_tokens=160, temp=0.8):
        return text
    return _chat


class ApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._servers = []
        cls.base = {}
        for name, handler in (("health", HealthHandler),
                              ("briefing", BriefingHandler),
                              ("director", DirectorHandler),
                              ("coach", CoachHandler)):
            srv = ThreadingHTTPServer(("127.0.0.1", 0), handler)
            srv.daemon_threads = True
            t = threading.Thread(target=srv.serve_forever,
                                 kwargs={"poll_interval": 0.05},
                                 daemon=True)
            t.start()
            cls._servers.append((srv, t))
            cls.base[name] = "http://127.0.0.1:%d" % srv.server_address[1]

    @classmethod
    def tearDownClass(cls):
        for srv, t in cls._servers:
            srv.shutdown()
            srv.server_close()
            t.join(timeout=10)

    def setUp(self):
        common.reset_rate_limit()
        self._real_chat = core.chat
        self.addCleanup(setattr, core, "chat", self._real_chat)

    # --- health: always 200 status probe --------------------------------
    def test_health_shape(self):
        status, body, headers = _call(self.base["health"], "/api/health",
                                      method="GET")
        self.assertEqual(status, 200)
        d = json.loads(body)
        self.assertTrue(d["ok"])
        self.assertFalse(d["meta_configured"])
        self.assertTrue(d["model"])
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "*")

    # --- unconfigured: content endpoints 503, game falls back ----------
    def test_unconfigured_returns_503(self):
        for name, payload in (
                ("briefing", {"level": 1, "level_name": "NEON DRIFT",
                              "hp_pct": 100, "kills": 0}),
                ("director", {"level": 1, "hp_frac": 1.0,
                              "kills_per_min": 5.0, "deaths": 0}),
                ("coach", {"score": 0, "kills": 0, "level_reached": 1,
                           "deaths": 0, "victory": False})):
            status, body, headers = _call(self.base[name], "/api/" + name,
                                          payload)
            self.assertEqual(status, 503, name)
            d = json.loads(body)
            self.assertEqual(d["source"], "fallback", name)
            self.assertEqual(headers.get("Access-Control-Allow-Origin"),
                             "*", name)

    # --- live shapes (stubbed Meta API) ---------------------------------
    def test_briefing_live_shape_and_caps(self):
        core.chat = _fake_chat(json.dumps(
            {"briefing": "B" * 500, "taunt": "T", "tip": "tip"}))
        status, body, _h = _call(
            self.base["briefing"], "/api/briefing",
            {"level": 2, "level_name": "CRIMSON BELT",
             "hp_pct": 80, "kills": 10})
        self.assertEqual(status, 200)
        d = json.loads(body)
        self.assertEqual(len(d["briefing"]), 220)
        self.assertEqual(d["taunt"], "T")
        self.assertEqual(d["tip"], "tip")
        self.assertTrue(d["source"].startswith("meta:"))

    def test_director_live_clamps(self):
        core.chat = _fake_chat(json.dumps(
            {"spawn_interval_mult": 99, "enemy_scale_mult": -5,
             "tip": "Y" * 500}))
        status, body, _h = _call(
            self.base["director"], "/api/director",
            {"level": 3, "hp_frac": 0.5,
             "kills_per_min": 8.0, "deaths": 0})
        self.assertEqual(status, 200)
        d = json.loads(body)
        self.assertEqual(d["spawn_interval_mult"], 1.4)
        self.assertEqual(d["enemy_scale_mult"], 0.8)
        self.assertEqual(len(d["tip"]), 160)
        self.assertTrue(d["source"].startswith("meta:"))

    def test_coach_live_shape_and_cap(self):
        core.chat = _fake_chat("Z" * 500)
        status, body, _h = _call(
            self.base["coach"], "/api/coach",
            {"score": 9000, "kills": 40, "level_reached": 3,
             "deaths": 1, "victory": False})
        self.assertEqual(status, 200)
        d = json.loads(body)
        self.assertEqual(len(d["advice"]), 300)
        self.assertTrue(d["source"].startswith("meta:"))

    # --- garbage in: sanitized, never 500 -------------------------------
    def test_garbage_inputs_sanitized(self):
        core.chat = _fake_chat(json.dumps(
            {"spawn_interval_mult": 1.0, "enemy_scale_mult": 1.0,
             "tip": "ok"}))
        status, _b, _h = _call(
            self.base["director"], "/api/director",
            {"level": "abc", "hp_frac": "zzz", "kills_per_min": [1],
             "deaths": {"n": 1}})
        self.assertEqual(status, 200)
        status, _b, _h = _call(
            self.base["briefing"], "/api/briefing", "not-a-dict",
            raw=b"not json{{{")
        self.assertIn(status, (200, 503))
        big = b"x" * (common.MAX_BODY + 1)
        status, _b, _h = _call(self.base["coach"], "/api/coach", None,
                               raw=big)
        self.assertIn(status, (200, 503))

    # --- rate limit ------------------------------------------------------
    def test_rate_limit_429(self):
        for _i in range(common.RATE_MAX):
            status, _b, _h = _call(
                self.base["briefing"], "/api/briefing", {"level": 1})
            self.assertEqual(status, 503)  # unkeyed, but allowed through
        status, body, headers = _call(
            self.base["briefing"], "/api/briefing", {"level": 1})
        self.assertEqual(status, 429)
        self.assertIn("rate limited", body)
        self.assertEqual(headers.get("Retry-After"), str(common.RETRY_AFTER))
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "*")

    def test_rate_limit_is_per_ip(self):
        for _i in range(common.RATE_MAX):
            _call(self.base["health"], "/api/health", method="GET")
        status, _b, _h = _call(self.base["health"], "/api/health",
                               method="GET")
        self.assertEqual(status, 429)
        status, _b, _h = _call(
            self.base["health"], "/api/health", method="GET",
            headers={"X-Forwarded-For": "9.9.9.9"})
        self.assertEqual(status, 200)

    def test_rate_window_expiry(self):
        self.assertFalse(common.rate_limited("w", now=1000.0))
        for _i in range(common.RATE_MAX - 1):
            common.rate_limited("w", now=1000.0)
        self.assertTrue(common.rate_limited("w", now=1000.0))
        self.assertFalse(
            common.rate_limited("w", now=1000.0 + common.RATE_WINDOW + 1))

    # --- CORS ------------------------------------------------------------
    def test_options_preflight(self):
        status, _b, headers = _call(
            self.base["director"], "/api/director", method="OPTIONS")
        self.assertEqual(status, 204)
        self.assertIn("POST", headers.get("Access-Control-Allow-Methods",
                                           ""))
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "*")


if __name__ == "__main__":
    unittest.main(verbosity=2)
