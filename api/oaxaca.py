"""
Oaxaca-Blinder decompositie endpoint — MOCK versie (stap 2).

Verwacht POST body:
{
    "rows": [
        {"uurloon": 25.5, "geslacht": "m", "functieniveau": 12, "ancienniteit": 3.5, "opleidingsniveau": "hooggeschoold"},
        ...
    ],
    "rechtsgrondslag": "loonkloof analyse Q2 2024"
}

Retourneert (MOCK — echte OLS + statsmodels komt in stap 3):
{
    "kind": "oaxaca_blinder",
    "runtime": "mock",
    "n_m": 12, "n_v": 8,
    "coefficients": [
        {"variabele": "functieniveau", "beta_m": 0.042, "beta_v": 0.038, "p_value": 0.001, "kloof_bijdrage": 1.20},
        ...
    ],
    "endowment_gap": 1.85,
    "coefficient_gap": 0.42,
    "raw_gap": 2.27,
    "r_squared_m": 0.71, "r_squared_v": 0.68
}

Auth: HMAC-SHA256 signatuur via `x-stats-signature` header verwacht wanneer STATS_SIGNING_SECRET
env var gezet is; anders open (voor lokale test). Client (Next.js server action) tekent
`{timestamp}.{body_sha256}` met dezelfde secret.
"""

from http.server import BaseHTTPRequestHandler
import json
import os
import hmac
import hashlib
import time


MAX_SKEW_SECONDS = 300  # HMAC timestamp mag max 5 min oud zijn


def verify_signature(headers, body: bytes) -> tuple[bool, str]:
    secret = os.environ.get("STATS_SIGNING_SECRET")
    if not secret:
        return True, "no-secret-configured"

    sig = headers.get("x-stats-signature", "")
    ts = headers.get("x-stats-timestamp", "")
    if not sig or not ts:
        return False, "missing signature headers"

    try:
        ts_int = int(ts)
    except ValueError:
        return False, "invalid timestamp"

    if abs(time.time() - ts_int) > MAX_SKEW_SECONDS:
        return False, "timestamp skew too large"

    body_hash = hashlib.sha256(body).hexdigest()
    payload = f"{ts}.{body_hash}".encode()
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()

    if not hmac.compare_digest(expected, sig):
        return False, "signature mismatch"

    return True, "ok"


def mock_decompose(rows: list[dict]) -> dict:
    """Placeholder decompositie — bewijst input/output shape zonder echte statistiek."""
    m_rows = [r for r in rows if r.get("geslacht") == "m"]
    v_rows = [r for r in rows if r.get("geslacht") == "v"]

    def avg(items, key):
        vals = [float(x.get(key, 0)) for x in items if x.get(key) is not None]
        return sum(vals) / len(vals) if vals else 0.0

    avg_m = avg(m_rows, "uurloon")
    avg_v = avg(v_rows, "uurloon")
    raw_gap = avg_m - avg_v

    # Mock decomposition: 70% endowment, 30% coefficient — echte cijfers komen uit OLS
    endowment = round(raw_gap * 0.70, 4)
    coefficient = round(raw_gap * 0.30, 4)

    return {
        "kind": "oaxaca_blinder",
        "runtime": "mock",
        "n_m": len(m_rows),
        "n_v": len(v_rows),
        "avg_uurloon_m": round(avg_m, 4),
        "avg_uurloon_v": round(avg_v, 4),
        "raw_gap": round(raw_gap, 4),
        "endowment_gap": endowment,
        "coefficient_gap": coefficient,
        "coefficients": [
            {"variabele": "functieniveau",   "beta_m": 0.042, "beta_v": 0.038, "p_value": 0.001, "kloof_bijdrage": round(raw_gap * 0.55, 4)},
            {"variabele": "ancienniteit",    "beta_m": 0.008, "beta_v": 0.011, "p_value": 0.340, "kloof_bijdrage": round(raw_gap * 0.10, 4)},
            {"variabele": "opleidingsniveau","beta_m": 0.156, "beta_v": 0.148, "p_value": 0.020, "kloof_bijdrage": round(raw_gap * 0.20, 4)},
        ],
        "r_squared_m": 0.71,
        "r_squared_v": 0.68,
        "note": "Mock output — vervangen door statsmodels.OLS in stap 3.",
    }


class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        headers_lower = {k.lower(): v for k, v in self.headers.items()}
        ok, reason = verify_signature(headers_lower, body)
        if not ok:
            self._respond(401, {"error": "unauthorized", "reason": reason})
            return

        try:
            payload = json.loads(body.decode() or "{}")
        except json.JSONDecodeError as e:
            self._respond(400, {"error": "invalid json", "detail": str(e)})
            return

        rows = payload.get("rows")
        if not isinstance(rows, list):
            self._respond(400, {"error": "missing or invalid 'rows' array"})
            return

        if len(rows) == 0:
            self._respond(400, {"error": "rows array is empty"})
            return

        try:
            result = mock_decompose(rows)
        except Exception as e:
            self._respond(500, {"error": "decomposition failed", "detail": str(e)})
            return

        # Echo rechtsgrondslag voor audit-trail terug naar caller
        result["rechtsgrondslag"] = payload.get("rechtsgrondslag", "not-provided")

        self._respond(200, result)

    def do_GET(self):
        self._respond(405, {"error": "method not allowed — use POST"})

    def _respond(self, status: int, body: dict):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())
