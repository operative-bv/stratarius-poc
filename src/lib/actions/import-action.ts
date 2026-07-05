"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { ImportState } from "./import-types";

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

    const header = lines[0].split(",").map((h) => h.trim().toLowerCase());
    const col = (row: string[], name: string): string => {
        const idx = header.indexOf(name);
        return idx >= 0 ? row[idx]?.trim() ?? "" : "";
    };

    const result = { created: 0, skipped: 0, errors: [] as string[] };

    for (let i = 1; i < lines.length; i++) {
        const row = lines[i].split(",");
        const naam = col(row, "naam");
        const geslacht = col(row, "geslacht").toLowerCase();
        const geboortedatum = col(row, "geboortedatum");
        const opleidingsniveau = col(row, "opleidingsniveau") || "middel_geschoold";
        const team = col(row, "team");
        const status = col(row, "status").toLowerCase() || "bediende";
        const pc = col(row, "pc") || (status === "arbeider" ? "124" : "200");
        const brutoRaw = col(row, "bruto");
        const bruto = brutoRaw ? Number(brutoRaw) : 0;

        if (!naam) {
            result.errors.push(`Rij ${i}: naam ontbreekt`);
            result.skipped++;
            continue;
        }
        if (!["m", "v", "x"].includes(geslacht)) {
            result.errors.push(`Rij ${i} (${naam}): ongeldig geslacht "${geslacht}" (verwacht m/v/x)`);
            result.skipped++;
            continue;
        }
        if (!geboortedatum || !/^\d{4}-\d{2}-\d{2}$/.test(geboortedatum)) {
            result.errors.push(`Rij ${i} (${naam}): geboortedatum moet YYYY-MM-DD zijn`);
            result.skipped++;
            continue;
        }
        if (bruto <= 0) {
            result.errors.push(`Rij ${i} (${naam}): bruto moet > 0 zijn`);
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
            result.errors.push(`Rij ${i} (${naam}): team "${team}" niet gevonden en kon niet worden aangemaakt`);
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
            result.errors.push(`Rij ${i} (${naam}): persoon insert faalde — ${persoonErr?.message}`);
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
            result.errors.push(`Rij ${i} (${naam}): contract insert faalde — ${contractErr?.message}`);
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
            result.errors.push(`Rij ${i} (${naam}): fact_looncomponent faalde — ${factErr.message}`);
            result.skipped++;
            continue;
        }

        result.created++;
    }

    revalidatePath(`/dashboard/${accountSlug}`);
    return { error: null, result };
}
