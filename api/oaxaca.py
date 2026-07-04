"""
Oaxaca-Blinder decompositie endpoint met OLS via numpy (statsmodels-vrij).

Model:
    log(uurloon) = β_0 + β_1 * functieniveau + β_2 * ancienniteit + β_3 * opleiding_dummy + ε

Twee regressies: één op mannelijke subset, één op vrouwelijke subset, plus pooled.
Oaxaca-Blinder two-fold decompositie:
    raw_gap = mean(log(uurloon_M)) - mean(log(uurloon_V))
    endowment  = (X̄_M - X̄_V) · β_pooled          # verschil in observables
    coefficient = X̄_M · (β_M - β_pooled) + X̄_V · (β_pooled - β_V)   # verschil in beloningsstructuur

Auth via HMAC-SHA256 signatuur als STATS_SIGNING_SECRET env-var gezet is.

Bundle-note: statsmodels + pandas overschrijden de 250MB Vercel Python function limit.
Deze implementatie doet OLS handmatig met numpy en t-CDF via scipy.stats om onder de limiet te blijven.
"""

from http.server import BaseHTTPRequestHandler
import json
import os
import hmac
import hashlib
import time

import numpy as np
from scipy import stats


MAX_SKEW_SECONDS = 300


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


REQUIRED_COLUMNS = ("uurloon", "geslacht", "functieniveau", "ancienniteit", "opleidingsniveau")


def _to_float(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def prepare_arrays(rows: list[dict]):
    """Bouw feature-matrix X (zonder constante), log_y, gender-array en kolomnamen."""
    n = len(rows)
    uurloon = np.array([max(_to_float(r.get("uurloon"), 0.01), 0.01) for r in rows], dtype=float)
    log_y = np.log(uurloon)
    functieniveau = np.array([_to_float(r.get("functieniveau"), 0.0) for r in rows], dtype=float)
    ancienniteit = np.array([_to_float(r.get("ancienniteit"), 0.0) for r in rows], dtype=float)
    gender = np.array([str(r.get("geslacht") or "") for r in rows])
    opl = [str(r.get("opleidingsniveau") or "") for r in rows]

    # Ref-categorie: middel_geschoold -> beide dummies 0
    dum_laag = np.array([1.0 if x == "laaggeschoold" else 0.0 for x in opl], dtype=float)
    dum_hoog = np.array([1.0 if x == "hooggeschoold" else 0.0 for x in opl], dtype=float)

    X = np.column_stack([functieniveau, ancienniteit, dum_laag, dum_hoog])
    colnames = ["functieniveau", "ancienniteit", "opl_laaggeschoold", "opl_hooggeschoold"]
    return X, log_y, gender, uurloon, colnames


def ols_fit(X_features: np.ndarray, y: np.ndarray) -> dict:
    """OLS met handmatige constante. Retourneert betas, p-values, R², X̄ (incl. constante)."""
    n = X_features.shape[0]
    X = np.column_stack([np.ones(n), X_features])
    k = X.shape[1]

    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    residuals = y - X @ beta
    ss_res = float(np.sum(residuals ** 2))
    ss_tot = float(np.sum((y - y.mean()) ** 2))
    r_squared = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0

    dof = max(n - k, 1)
    sigma2 = ss_res / dof

    try:
        cov = sigma2 * np.linalg.inv(X.T @ X)
        se = np.sqrt(np.maximum(np.diag(cov), 0.0))
    except np.linalg.LinAlgError:
        se = np.full(k, np.inf)

    with np.errstate(divide="ignore", invalid="ignore"):
        t_stats = np.where(se > 0, beta / se, 0.0)
    pvals = 2.0 * stats.t.sf(np.abs(t_stats), df=dof)

    x_bar = np.concatenate([[1.0], X_features.mean(axis=0)])

    return {
        "beta": beta,
        "pvalues": pvals,
        "rsquared": r_squared,
        "x_bar": x_bar,
    }


def oaxaca_blinder(rows: list[dict]) -> dict:
    X, log_y, gender, uurloon, colnames = prepare_arrays(rows)

    m_mask = gender == "m"
    v_mask = gender == "v"
    n_m = int(m_mask.sum())
    n_v = int(v_mask.sum())

    if n_m < 3 or n_v < 3:
        raise ValueError(f"Onvoldoende data voor OLS: n_M={n_m}, n_V={n_v} (min 3 per groep)")

    m = ols_fit(X[m_mask], log_y[m_mask])
    v = ols_fit(X[v_mask], log_y[v_mask])
    pooled = ols_fit(X, log_y)

    diff_x = m["x_bar"] - v["x_bar"]
    endowment_log = float(diff_x @ pooled["beta"])
    coef_m_part = float(m["x_bar"] @ (m["beta"] - pooled["beta"]))
    coef_v_part = float(v["x_bar"] @ (pooled["beta"] - v["beta"]))
    coefficient_log = coef_m_part + coef_v_part

    raw_gap_log = float(log_y[m_mask].mean() - log_y[v_mask].mean())
    mean_uurloon = float(uurloon.mean())

    coeffs = []
    for i, name in enumerate(colnames, start=1):  # skip constante (index 0)
        beta_m = float(m["beta"][i])
        beta_v = float(v["beta"][i])
        p_m = float(m["pvalues"][i])
        p_v = float(v["pvalues"][i])
        diff_var = float(m["x_bar"][i] - v["x_bar"][i])
        beta_pooled = float(pooled["beta"][i])
        contribution_eur = diff_var * beta_pooled * mean_uurloon
        coeffs.append({
            "variabele": name,
            "beta_m": round(beta_m, 4),
            "beta_v": round(beta_v, 4),
            "p_value": round(min(p_m, p_v), 4),
            "kloof_bijdrage": round(contribution_eur, 4),
        })

    return {
        "kind": "oaxaca_blinder",
        "runtime": "numpy-OLS",
        "n_m": n_m,
        "n_v": n_v,
        "avg_uurloon_m": round(float(uurloon[m_mask].mean()), 4),
        "avg_uurloon_v": round(float(uurloon[v_mask].mean()), 4),
        "raw_gap": round(raw_gap_log * mean_uurloon, 4),
        "raw_gap_log": round(raw_gap_log, 4),
        "endowment_gap": round(endowment_log * mean_uurloon, 4),
        "coefficient_gap": round(coefficient_log * mean_uurloon, 4),
        "coefficients": coeffs,
        "r_squared_m": round(m["rsquared"], 4),
        "r_squared_v": round(v["rsquared"], 4),
        "note": (
            "Model: log(uurloon) = f(functieniveau, ancienniteit, opleidingsniveau). "
            "Two-fold Oaxaca-Blinder met β_pooled. Log-gap × mean(uurloon) = EUR equivalent."
        ),
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
        if not isinstance(rows, list) or len(rows) == 0:
            self._respond(400, {"error": "missing or empty 'rows' array"})
            return

        if not isinstance(rows[0], dict):
            self._respond(400, {"error": "rows[0] must be an object"})
            return

        missing = [c for c in REQUIRED_COLUMNS if c not in rows[0]]
        if missing:
            self._respond(400, {"error": f"missing columns: {missing}"})
            return

        try:
            result = oaxaca_blinder(rows)
        except ValueError as e:
            self._respond(400, {"error": "insufficient data", "detail": str(e)})
            return
        except Exception as e:
            self._respond(500, {"error": "decomposition failed", "detail": str(e)})
            return

        result["rechtsgrondslag"] = payload.get("rechtsgrondslag", "not-provided")
        self._respond(200, result)

    def do_GET(self):
        self._respond(405, {"error": "method not allowed — use POST"})

    def _respond(self, status: int, body: dict):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())
