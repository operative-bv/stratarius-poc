"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { ImportState } from "./import-types";
import { generateDemoRows, type DemoRow } from "@/lib/demo-dataset";

async function importRows(accountSlug: string, rows: DemoRow[]): Promise<ImportState> {
    const supabase = await createClient();

    const [{ data: entData }, { data: funcData }, { data: scenData }] = await Promise.all([
        supabase.from("dim_legale_entiteit").select("legale_entiteit_id, owning_account_id").limit(1),
        supabase.from("dim_functie").select("functie_id, functienaam, owning_account_id"),
        supabase.from("dim_scenario").select("scenario_id").eq("kind", "baseline").limit(1),
    ]);
    const entiteit = entData?.[0];
    const functies = (funcData ?? []) as {
        functie_id: string;
        functienaam: string;
        owning_account_id: string;
    }[];
    const baselineId = scenData?.[0]?.scenario_id;

    if (!entiteit || !baselineId) {
        return { error: "Legale entiteit of baseline scenario ontbreekt", result: null };
    }

    const result = { created: 0, skipped: 0, errors: [] as string[] };

    for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const naam = r.naam;
        const geslacht = r.geslacht;
        const geboortedatum = r.geboortedatum;
        const opleidingsniveau = r.opleidingsniveau;
        const team = r.team;
        const status = r.status;
        const pc = r.pc;
        const bruto = r.bruto;

        if (!naam) {
            result.errors.push(`Rij ${i + 1}: naam ontbreekt`);
            result.skipped++;
            continue;
        }
        if (!["m", "v", "x"].includes(geslacht)) {
            result.errors.push(`Rij ${i + 1} (${naam}): ongeldig geslacht "${geslacht}"`);
            result.skipped++;
            continue;
        }
        if (!geboortedatum || !/^\d{4}-\d{2}-\d{2}$/.test(geboortedatum)) {
            result.errors.push(`Rij ${i + 1} (${naam}): geboortedatum moet YYYY-MM-DD zijn`);
            result.skipped++;
            continue;
        }
        if (bruto <= 0) {
            result.errors.push(`Rij ${i + 1} (${naam}): bruto moet > 0 zijn`);
            result.skipped++;
            continue;
        }

        let functie = functies.find((f) => f.functienaam.toLowerCase() === team.toLowerCase());
        if (!functie && team) {
            const { data: newFunc } = await supabase
                .from("dim_functie")
                .insert({ owning_account_id: entiteit.owning_account_id, functienaam: team, functieniveau: 10 })
                .select("functie_id, functienaam, owning_account_id")
                .single();
            if (newFunc) {
                functie = newFunc;
                functies.push(functie);
            }
        }
        if (!functie) {
            result.errors.push(`Rij ${i + 1} (${naam}): team "${team}" niet gevonden`);
            result.skipped++;
            continue;
        }

        const { data: persoonInsert, error: persoonErr } = await supabase
            .from("dim_persoon")
            .insert({
                owning_account_id: entiteit.owning_account_id,
                geslacht,
                geboortedatum,
                opleidingsniveau,
            })
            .select("persoon_id")
            .single();

        if (persoonErr || !persoonInsert) {
            result.errors.push(`Rij ${i + 1} (${naam}): persoon insert faalde — ${persoonErr?.message}`);
            result.skipped++;
            continue;
        }

        const { data: contractInsert, error: contractErr } = await supabase
            .from("dim_contract")
            .insert({
                persoon_id: persoonInsert.persoon_id,
                legale_entiteit_id: entiteit.legale_entiteit_id,
                functie_id: functie.functie_id,
                pc_id: pc,
                status,
                fte_breuk: 1.0,
                geldig_van: "2023-01-01",
            })
            .select("contract_id")
            .single();

        if (contractErr || !contractInsert) {
            result.errors.push(`Rij ${i + 1} (${naam}): contract insert faalde — ${contractErr?.message}`);
            result.skipped++;
            continue;
        }

        const { error: factErr } = await supabase.from("fact_looncomponent").insert({
            contract_id: contractInsert.contract_id,
            periode: "2024-06-01",
            component_id: "basisloon",
            scenario_id: baselineId,
            bedrag: bruto,
        });

        if (factErr) {
            result.errors.push(`Rij ${i + 1} (${naam}): fact_looncomponent faalde — ${factErr.message}`);
            result.skipped++;
            continue;
        }

        result.created++;
    }

    revalidatePath(`/dashboard/${accountSlug}`);
    return { error: null, result };
}

export async function importCsvAction(
    accountSlug: string,
    _prev: ImportState,
    formData: FormData,
): Promise<ImportState> {
    const file = formData.get("csv") as File | null;
    if (!file || file.size === 0) {
        return { error: "Geen bestand geselecteerd", result: null };
    }

    const text = await file.text();
    const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
    if (lines.length < 2) {
        return { error: "CSV moet header + minstens 1 rij bevatten", result: null };
    }

    const header = lines[0].split(",").map((h) => h.trim().toLowerCase());
    const col = (row: string[], name: string): string => {
        const idx = header.indexOf(name);
        return idx >= 0 ? row[idx]?.trim() ?? "" : "";
    };

    const rows: DemoRow[] = [];
    for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].split(",");
        const status = (col(parts, "status").toLowerCase() || "bediende") as DemoRow["status"];
        const opl = (col(parts, "opleidingsniveau") || "middel_geschoold") as DemoRow["opleidingsniveau"];
        const geslacht = col(parts, "geslacht").toLowerCase();
        rows.push({
            naam: col(parts, "naam"),
            geslacht: (geslacht === "m" || geslacht === "v" ? geslacht : "m") as "m" | "v",
            geboortedatum: col(parts, "geboortedatum"),
            opleidingsniveau: opl,
            team: col(parts, "team"),
            status,
            pc: col(parts, "pc") || (status === "arbeider" ? "124" : "200"),
            bruto: Number(col(parts, "bruto") || 0),
        });
    }

    return importRows(accountSlug, rows);
}

export async function loadDemoDatasetAction(
    accountSlug: string,
    _prev: ImportState,
    _formData: FormData,
): Promise<ImportState> {
    const rows = generateDemoRows(1000);
    return importRows(accountSlug, rows);
}
