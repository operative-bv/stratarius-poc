"use server";

import { createClient } from "@/lib/supabase/server";
import { callOaxacaService, type OaxacaRow } from "@/lib/oaxaca-client";
import type { OaxacaState } from "./oaxaca-types";

export async function runOaxacaAction(
    _prev: OaxacaState,
    _formData: FormData,
): Promise<OaxacaState> {
    const supabase = await createClient();

    const { data: martRows } = await supabase
        .from("mart_loonkloof")
        .select("persoon_id, uurloon_bruto, geslacht, functieniveau, ancienniteit_jaren")
        .eq("referentiedatum", "2024-06-30");
    const { data: personen } = await supabase
        .from("dim_persoon")
        .select("persoon_id, opleidingsniveau");
    const opleidingMap = new Map(
        (personen ?? []).map(
            (p: { persoon_id: string; opleidingsniveau: string }) => [p.persoon_id, p.opleidingsniveau],
        ),
    );

    const rows: OaxacaRow[] = (martRows ?? []).map(
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
        const result = await callOaxacaService(rows, "loonkloof analyse Q2 2024 via dashboard");
        return { result, error: null };
    } catch (e) {
        const msg = e instanceof Error ? e.message : "unknown error";
        return { result: null, error: msg };
    }
}
