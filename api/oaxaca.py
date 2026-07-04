"""
Oaxaca-Blinder decompositie endpoint met echte OLS via statsmodels.

Model:
    log(uurloon) = β_0 + β_1 * functieniveau + β_2 * ancienniteit + β_3 * opleiding_dummy + ε

Twee regressies: één op mannelijke subset, één op vrouwelijke subset.
Oaxaca-Blinder two-fold decompositie:
    raw_gap = mean(log(uurloon_M)) - mean(log(uurloon_V))
    endowment  = (X̄_M - X̄_V) · β_pooled          # verschil in observables
    coefficient = X̄_V · (β_M - β_V)                # verschil in beloningsstructuur
    residual   = raw_gap - endowment - coefficient  # interaction term

Auth via HMAC-SHA256 signatuur als STATS_SIGNING_SECRET env-var gezet is.
"""

from http.server import BaseHTTPRequestHandler
import json
import os
import hmac
import hashlib
import time

import pandas as pd
import numpy as np
import statsmodels.api as sm


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


def prepare_features(df: pd.DataFrame) -> pd.DataFrame:
    """Encode categorische variabelen: opleidingsniveau → dummies. Voeg constante toe."""
    # Log-transform uurloon (Oaxaca-conventie voor semi-elasticiteits-interpretatie)
    df = df.copy()
    df["log_uurloon"] = np.log(df["uurloon"].astype(float).clip(lower=0.01))
    df["functieniveau"] = pd.to_numeric(df["functieniveau"], errors="coerce").fillna(0)
    df["ancienniteit"] = pd.to_numeric(df["ancienniteit"], errors="coerce").fillna(0)

    # Dummy encoding voor opleidingsniveau — ref categorie 'middel_geschoold'
    opleiding_dummies = pd.get_dummies(df["opleidingsniveau"], prefix="opl", dtype=float)
    for col in ["opl_laaggeschoold", "opl_middel_geschoold", "opl_hooggeschoold"]:
        if col not in opleiding_dummies.columns:
            opleiding_dummies[col] = 0.0
    if "opl_middel_geschoold" in opleiding_dummies.columns:
        opleiding_dummies = opleiding_dummies.drop(columns=["opl_middel_geschoold"])

    features = pd.concat([df[["functieniveau", "ancienniteit"]], opleiding_dummies], axis=1)
    features = features.astype(float)
    return features


def oaxaca_blinder(df: pd.DataFrame) -> dict:
    """Voer echte OLS + Oaxaca-Blinder decompositie uit.

    Retourneert dict met per-variabele coëfficiënten + p-values + endowment/coefficient split.
    """
    features_all = prepare_features(df)
    df = df.copy()
    df["log_uurloon"] = np.log(df["uurloon"].astype(float).clip(lower=0.01))

    m_mask = df["geslacht"] == "m"
    v_mask = df["geslacht"] == "v"

    X_m = sm.add_constant(features_all[m_mask], has_constant="add")
    X_v = sm.add_constant(features_all[v_mask], has_constant="add")
    X_pooled = sm.add_constant(features_all, has_constant="add")

    y_m = df.loc[m_mask, "log_uurloon"]
    y_v = df.loc[v_mask, "log_uurloon"]
    y_all = df["log_uurloon"]

    n_m = int(m_mask.sum())
    n_v = int(v_mask.sum())

    # Guard: minstens 3 observaties per groep voor stabiele OLS
    if n_m < 3 or n_v < 3:
        raise ValueError(f"Onvoldoende data voor OLS: n_M={n_m}, n_V={n_v} (min 3 per groep)")

    ols_m = sm.OLS(y_m, X_m).fit()
    ols_v = sm.OLS(y_v, X_v).fit()
    ols_pooled = sm.OLS(y_all, X_pooled).fit()

    # Mean X-vectoren per groep (voor decompositie)
    X_m_bar = X_m.mean()
    X_v_bar = X_v.mean()

    # Two-fold Oaxaca-Blinder (Blinder 1973 / Oaxaca 1973)
    # E = (X̄_M - X̄_V) · β_pooled   (endowment / explained)
    # C = X̄_V · (β_M - β_pooled) + X̄_M · (β_pooled - β_V)   (coefficient / unexplained)
    diff_X = X_m_bar - X_v_bar
    endowment_effect = float(diff_X @ ols_pooled.params)
    coefficient_m_part = float(X_m_bar @ (ols_m.params - ols_pooled.params))
    coefficient_v_part = float(X_v_bar @ (ols_pooled.params - ols_v.params))
    coefficient_effect = coefficient_m_part + coefficient_v_part

    raw_gap_log = float(y_m.mean() - y_v.mean())

    # Per-variabele bijdrage aan endowment (voor UI-tabel)
    coeffs = []
    for var in X_m.columns:
        if var == "const":
            continue
        beta_m = float(ols_m.params.get(var, 0))
        beta_v = float(ols_v.params.get(var, 0))
        p_m = float(ols_m.pvalues.get(var, 1.0))
        p_v = float(ols_v.pvalues.get(var, 1.0))
        # Kloof-bijdrage = (X̄_m - X̄_v) * β_pooled per variabele
        diff_var = float(X_m_bar.get(var, 0) - X_v_bar.get(var, 0))
        beta_pooled = float(ols_pooled.params.get(var, 0))
        contribution_log = diff_var * beta_pooled
        # Converteer log-gap naar EUR-equivalent (approximation via mean uurloon)
        mean_uurloon = float(df["uurloon"].mean())
        contribution_eur = contribution_log * mean_uurloon
        coeffs.append({
            "variabele": var,
            "beta_m": round(beta_m, 4),
            "beta_v": round(beta_v, 4),
            "p_value": round(min(p_m, p_v), 4),
            "kloof_bijdrage": round(contribution_eur, 4),
        })

    # Convert log-gap terug naar EUR (approximation via mean loonniveau)
    mean_uurloon = float(df["uurloon"].mean())
    raw_gap_eur = raw_gap_log * mean_uurloon
    endowment_eur = endowment_effect * mean_uurloon
    coefficient_eur = coefficient_effect * mean_uurloon

    return {
        "kind": "oaxaca_blinder",
        "runtime": "statsmodels-OLS",
        "n_m": n_m,
        "n_v": n_v,
        "avg_uurloon_m": round(float(df.loc[m_mask, "uurloon"].mean()), 4),
        "avg_uurloon_v": round(float(df.loc[v_mask, "uurloon"].mean()), 4),
        "raw_gap": round(raw_gap_eur, 4),
        "raw_gap_log": round(raw_gap_log, 4),
        "endowment_gap": round(endowment_eur, 4),
        "coefficient_gap": round(coefficient_eur, 4),
        "coefficients": coeffs,
        "r_squared_m": round(float(ols_m.rsquared), 4),
        "r_squared_v": round(float(ols_v.rsquared), 4),
        "note": (
            f"Model: log(uurloon) = f(functieniveau, ancienniteit, opleidingsniveau). "
            f"Two-fold Oaxaca-Blinder met β_pooled. Log-gap × mean(uurloon) = EUR equivalent."
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

        try:
            df = pd.DataFrame(rows)
            required = {"uurloon", "geslacht", "functieniveau", "ancienniteit", "opleidingsniveau"}
            missing = required - set(df.columns)
            if missing:
                self._respond(400, {"error": f"missing columns: {sorted(missing)}"})
                return
            result = oaxaca_blinder(df)
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
