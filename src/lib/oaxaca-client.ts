import crypto from "node:crypto";
import { headers as requestHeaders } from "next/headers";

export type OaxacaRow = {
    uurloon: number;
    geslacht: string;
    functieniveau: number;
    ancienniteit: number;
    opleidingsniveau: string;
};

export type OaxacaCoefficient = {
    variabele: string;
    beta_m: number;
    beta_v: number;
    p_value: number;
    kloof_bijdrage: number;
};

export type OaxacaResult = {
    kind: string;
    runtime: string;
    n_m: number;
    n_v: number;
    avg_uurloon_m: number;
    avg_uurloon_v: number;
    raw_gap: number;
    endowment_gap: number;
    coefficient_gap: number;
    coefficients: OaxacaCoefficient[];
    r_squared_m: number;
    r_squared_v: number;
    note?: string;
    rechtsgrondslag?: string;
};

export async function callOaxacaService(
    rows: OaxacaRow[],
    rechtsgrondslag: string,
): Promise<OaxacaResult> {
    // Base URL prioriteit:
    //   1. PYTHON_SERVICE_URL env var — voor lokale dev die tegen prod-Python praat
    //      (vercel dev serveert Python endpoints niet lokaal in Next.js projecten)
    //   2. NEXT_PUBLIC_APP_URL env var — expliciete override
    //   3. Huidige request headers — normaal gedrag in prod (self-call)
    let baseUrl = process.env.PYTHON_SERVICE_URL ?? process.env.NEXT_PUBLIC_APP_URL;
    if (!baseUrl) {
        const h = requestHeaders();
        const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
        const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
        baseUrl = `${proto}://${host}`;
    }

    const body = JSON.stringify({ rows, rechtsgrondslag });
    const headers: Record<string, string> = { "Content-Type": "application/json" };

    // HMAC signing als STATS_SIGNING_SECRET gezet is (Python endpoint honoreert dezelfde)
    const secret = process.env.STATS_SIGNING_SECRET;
    if (secret) {
        const timestamp = Math.floor(Date.now() / 1000).toString();
        const bodyHash = crypto.createHash("sha256").update(body).digest("hex");
        const payload = `${timestamp}.${bodyHash}`;
        const signature = crypto.createHmac("sha256", secret).update(payload).digest("hex");
        headers["x-stats-timestamp"] = timestamp;
        headers["x-stats-signature"] = signature;
    }

    const url = `${baseUrl}/api/oaxaca`;
    const res = await fetch(url, {
        method: "POST",
        headers,
        body,
        cache: "no-store",
        redirect: "manual",  // volg redirects NIET — help diagnostics als iets ons naar HTML stuurt
    });

    const contentType = res.headers.get("content-type") ?? "";
    if (!res.ok || res.status >= 300) {
        const errBody = await res.text();
        throw new Error(`oaxaca service ${res.status} at ${url} (${contentType}): ${errBody.slice(0, 200)}`);
    }
    if (!contentType.includes("application/json")) {
        const errBody = await res.text();
        throw new Error(`oaxaca service returned non-JSON at ${url} (${contentType}, status ${res.status}): ${errBody.slice(0, 200)}`);
    }

    return (await res.json()) as OaxacaResult;
}
