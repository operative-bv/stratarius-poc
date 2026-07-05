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

    const { data: martRows, error: martErr } = await supabase
        .from("mart_loonkloof")
        .select("persoon_id, uurloon_bruto, geslacht, functieniveau, ancienniteit_jaren")
        .eq("referentiedatum", "2026-06-30")
        .in("legale_entiteit_id", entiteitIds);
    if (martErr) {
        return { result: null, error: `Loonkloof-mart query faalde: ${martErr.message}` };
    }
    const rows_data = martRows ?? [];
    if (rows_data.length === 0) {
        return { result: null, error: "Geen loonkloof-data voor huidige populatie/periode." };
    }

    // dim_persoon.opleidingsniveau is GDPR-protected (T-034). Query via
    // de RLS'd table (RLS filtert op owning_account_id) mét beperking
    // tot alleen de persoon_id's die we ook uit de mart hebben.
    const persoonIds = Array.from(new Set(rows_data.map((r: { persoon_id: string }) => r.persoon_id)));
    const { data: personen, error: personenErr } = await supabase
        .from("dim_persoon")
        .select("persoon_id, opleidingsniveau")
        .in("persoon_id", persoonIds);
    if (personenErr) {
        return { result: null, error: `Persoon-lookup faalde: ${personenErr.message}` };
    }
    const opleidingMap = new Map(
        (personen ?? []).map(
            (p: { persoon_id: string; opleidingsniveau: string }) => [p.persoon_id, p.opleidingsniveau],
        ),
    );

    const rows: OaxacaRow[] = rows_data.map(
        (r: {
            persoon_id: string;
            uurloon_bruto: number;
            geslacht: string;
            functieniveau: number;
            ancienniteit_jaren: number;
        }) => ({
            uurloon: Number(r.uurloon_bruto),
            geslacht: r.geslacht,
            functieniveau: Number(r.functieniveau),
            ancienniteit: Number(r.ancienniteit_jaren),
            opleidingsniveau: opleidingMap.get(r.persoon_id) ?? "onbekend",
        }),
    );

    try {
        const result = await callOaxacaService(rows, "loonkloof analyse Q2 2026 via dashboard");
        return { result, error: null };
    } catch (e) {
        const msg = e instanceof Error ? e.message : "unknown error";
        return { result: null, error: msg };
    }
}
