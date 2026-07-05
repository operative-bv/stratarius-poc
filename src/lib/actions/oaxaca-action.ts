"use server";

import { createClient } from "@/lib/supabase/server";
import { callOaxacaService, type OaxacaRow } from "@/lib/oaxaca-client";
import type { OaxacaState } from "./oaxaca-types";

export async function runOaxacaAction(
    _prev: OaxacaState,
    _formData: FormData,
): Promise<OaxacaState> {
    const supabase = await createClient();

    // ISS-077: mart_loonkloof is materialized view die RLS omzeilt.
    // Filter expliciet op tenant's legale_entiteit_id(s) via de RLS'd
    // dim_legale_entiteit query.
    const { data: entiteitenData, error: entErr } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id");
    if (entErr) {
        return { result: null, error: `Tenant lookup faalde: ${entErr.message}` };
    }
    const entiteitIds = (entiteitenData ?? []).map(
        (e: { legale_entiteit_id: string }) => e.legale_entiteit_id,
    );
    if (entiteitIds.length === 0) {
        return { result: null, error: "Geen legale entiteit voor deze tenant." };
    }

    // mart_loonkloof heeft nu RLS op owning_account_id — Postgres filtert automatisch.
    const { data: martRows, error: martErr } = await supabase
        .from("mart_loonkloof")
        .select("persoon_id, uurloon_bruto, geslacht, functieniveau, ancienniteit_jaren")
        .eq("referentiedatum", "2026-06-30");
    if (martErr) {
        return { result: null, error: `Loonkloof-mart query faalde: ${martErr.message}` };
    }
    const rows_data = martRows ?? [];
    if (rows_data.length === 0) {
        return { result: null, error: "Geen loonkloof-data voor huidige populatie/periode." };
    }

    // dim_persoon.opleidingsniveau is GDPR-protected (T-034, ISS-086).
    // Access via RPC met rechtsgrondslag audit. RPC filtert tenant-side.
    const persoonIds = Array.from(new Set(rows_data.map((r: { persoon_id: string }) => r.persoon_id)));
    const { data: personen, error: personenErr } = await supabase.rpc(
        "get_oaxaca_persoon_opleiding",
        {
            p_persoon_ids: persoonIds,
            p_rechtsgrondslag: "loonkloof-analyse Oaxaca-Blinder decompositie (POC demo)",
        },
    );
    if (personenErr) {
        return { result: null, error: `Persoon-lookup faalde: ${personenErr.message}` };
    }
    const personenRows = (personen ?? []) as Array<{
        persoon_id: string;
        opleidingsniveau: string;
    }>;
    const opleidingMap = new Map(personenRows.map((p) => [p.persoon_id, p.opleidingsniveau]));

    // Parse-boundary: DB waardes zijn `string` op type-niveau maar de
    // Python OaxacaRow verwacht domain unions ("m"|"v", 3 opleidings-
    // niveaus). Filter rijen die niet passen ipv onveilig te casten.
    const validOpleidingen = new Set(["laaggeschoold", "middel_geschoold", "hooggeschoold"]);
    const rows: OaxacaRow[] = [];
    for (const raw of rows_data as Array<{
        persoon_id: string;
        uurloon_bruto: number;
        geslacht: string;
        functieniveau: number;
        ancienniteit_jaren: number;
    }>) {
        if (raw.geslacht !== "m" && raw.geslacht !== "v") continue;
        const opl = opleidingMap.get(raw.persoon_id);
        if (!opl || !validOpleidingen.has(opl)) continue;
        rows.push({
            uurloon: Number(raw.uurloon_bruto),
            geslacht: raw.geslacht,
            functieniveau: Number(raw.functieniveau),
            ancienniteit: Number(raw.ancienniteit_jaren),
            opleidingsniveau: opl as OaxacaRow["opleidingsniveau"],
        });
    }
    if (rows.length === 0) {
        return { result: null, error: "Geen valide loonkloof-rijen (geslacht + opleidingsniveau checks)." };
    }

    try {
        const result = await callOaxacaService(rows, "loonkloof analyse Q2 2026 via dashboard");
        return { result, error: null };
    } catch (e) {
        const msg = e instanceof Error ? e.message : "unknown error";
        return { result: null, error: msg };
    }
}
