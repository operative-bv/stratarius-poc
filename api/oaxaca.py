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
    """OLS met handmatige constante.

    Dropt kolommen met (bijna) nul variantie in de subset om rank-deficiëntie te vermijden.
    Voor gedropte kolommen wordt β=0 en p=NaN teruggegeven zodat de output shape stabiel is.
    """
    n, k_full = X_features.shape

    # Detect constante kolommen -> rank-deficiëntie voorkomen
    col_std = X_features.std(axis=0)
    active_mask = col_std > 1e-10
    X_active = X_features[:, active_mask]
    k_active = X_active.shape[1]

    X = np.column_stack([np.ones(n), X_active])
    k = X.shape[1]  # k_active + 1 voor constante

    beta_active, *_ = np.linalg.lstsq(X, y, rcond=None)
    residuals = y - X @ beta_active
    ss_res = float(np.sum(residuals ** 2))
    ss_tot = float(np.sum((y - y.mean()) ** 2))
    r_squared = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0

    dof = max(n - k, 1)
    sigma2 = ss_res / dof

    try:
        cov = sigma2 * np.linalg.inv(X.T @ X)
        se_active = np.sqrt(np.maximum(np.diag(cov), 0.0))
    except np.linalg.LinAlgError:
        se_active = np.full(k, np.inf)

    with np.errstate(divide="ignore", invalid="ignore"):
        t_stats_active = np.where(se_active > 0, beta_active / se_active, 0.0)
    pvals_active = 2.0 * stats.t.sf(np.abs(t_stats_active), df=dof)

    # Expand terug naar volledige feature-ruimte (constante + k_full features)
    beta_full = np.zeros(k_full + 1)
    pvals_full = np.full(k_full + 1, np.nan)
    beta_full[0] = beta_active[0]
    pvals_full[0] = pvals_active[0]
    beta_full[1:][active_mask] = beta_active[1:]
    pvals_full[1:][active_mask] = pvals_active[1:]

    x_bar = np.concatenate([[1.0], X_features.mean(axis=0)])
    dropped = [bool(x) for x in ~active_mask]

    return {
        "beta": beta_full,
        "pvalues": pvals_full,
        "rsquared": r_squared,
        "x_bar": x_bar,
        "dropped": dropped,  # per feature (excl constante), True = geen variatie in subset
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
    for i, name in enumerate(colnames):  # i = index in feature-ruimte, +1 in beta/pvals
        beta_m = float(m["beta"][i + 1])
        beta_v = float(v["beta"][i + 1])
        p_m = m["pvalues"][i + 1]
        p_v = v["pvalues"][i + 1]
        diff_var = float(m["x_bar"][i + 1] - v["x_bar"][i + 1])
        beta_pooled = float(pooled["beta"][i + 1])
        contribution_eur = diff_var * beta_pooled * mean_uurloon

        dropped_m = m["dropped"][i]
        dropped_v = v["dropped"][i]
        dropped_pooled = pooled["dropped"][i]

        # Kies laagste p-value uit M/V; als beide NaN → variabele had geen variatie
        pvals_valid = [p for p in (p_m, p_v) if not np.isnan(p)]
        p_value = float(min(pvals_valid)) if pvals_valid else None

        coeffs.append({
            "variabele": name,
            "beta_m": round(beta_m, 4),
            "beta_v": round(beta_v, 4),
            "p_value": round(p_value, 4) if p_value is not None else None,
            "kloof_bijdrage": round(contribution_eur, 4),
            "dropped": bool(dropped_pooled or (dropped_m and dropped_v)),
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
