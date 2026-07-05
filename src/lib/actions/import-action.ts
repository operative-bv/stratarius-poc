"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { ImportState } from "./import-types";
import { generateDemoRows, type DemoRow } from "@/lib/demo-dataset";

async function bulkImport(accountSlug: string, rows: DemoRow[]): Promise<ImportState> {
    const supabase = await createClient();

    // ISS-080: expliciet error check ipv silent drop — voorkomt dat "entiteit
    // ontbreekt" wordt getoond terwijl het eigenlijk een RLS-block of timeout is.
    const [entRes, scenRes] = await Promise.all([
        supabase.from("dim_legale_entiteit").select("legale_entiteit_id").limit(1),
        supabase.from("dim_scenario").select("scenario_id").eq("kind", "baseline").limit(1),
    ]);
    if (entRes.error) {
        return { error: `Tenant lookup faalde: ${entRes.error.message}`, result: null };
    }
    if (scenRes.error) {
        return { error: `Scenario lookup faalde: ${scenRes.error.message}`, result: null };
    }
    const entiteitId = entRes.data?.[0]?.legale_entiteit_id;
    const baselineId = scenRes.data?.[0]?.scenario_id;

    if (!entiteitId) {
        return { error: "Nog geen legale entiteit — voltooi eerst de setup wizard.", result: null };
    }
    if (!baselineId) {
        return { error: "Baseline scenario ontbreekt — controleer setup wizard.", result: null };
    }

    // Één RPC call ipv 3× per rij HTTP round-trips.
    const { data, error } = await supabase.rpc("bulk_import_populatie", {
        p_legale_entiteit_id: entiteitId,
        p_scenario_id: baselineId,
        p_rows: rows,
    });

    if (error) {
        return { error: `Import faalde: ${error.message}`, result: null };
    }

    const row = (data ?? [])[0] as { created: number; skipped: number; errors: string[] } | undefined;
    revalidatePath(`/dashboard/${accountSlug}`);
    return {
        error: null,
        result: {
            created: row?.created ?? 0,
            skipped: row?.skipped ?? 0,
            errors: row?.errors ?? [],
        },
    };
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

    return bulkImport(accountSlug, rows);
}

export async function loadDemoDatasetAction(
    accountSlug: string,
    _prev: ImportState,
    _formData: FormData,
): Promise<ImportState> {
    const rows = generateDemoRows(1000);
    return bulkImport(accountSlug, rows);
}
