import crypto from "node:crypto";

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
    const baseUrl = process.env.NEXT_PUBLIC_APP_URL
        ?? (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "http://localhost:3000");

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

    const res = await fetch(`${baseUrl}/api/oaxaca`, {
        method: "POST",
        headers,
        body,
        cache: "no-store",
    });

    if (!res.ok) {
        const errBody = await res.text();
        throw new Error(`oaxaca service ${res.status}: ${errBody.slice(0, 200)}`);
    }

    return (await res.json()) as OaxacaResult;
}
