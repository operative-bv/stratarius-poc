"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { SetupState } from "./setup-types";

export async function completeSetupAction(
    accountSlug: string,
    _prev: SetupState,
    formData: FormData,
): Promise<SetupState> {
    const supabase = await createClient();

    const naam = String(formData.get("naam") ?? "").trim();
    const gewest = String(formData.get("gewest") ?? "vlaanderen");
    const werkgeverscategorie = Number(formData.get("werkgeverscategorie") ?? 1);
    const ondernemingsnr = String(formData.get("ondernemingsnr") ?? "").trim() || null;
    const accountId = String(formData.get("account_id") ?? "");

    if (!naam || !accountId) {
        return { error: "Naam en account_id verplicht" };
    }

    if (ondernemingsnr && !/^[01]\d{3}\.\d{3}\.\d{3}$/.test(ondernemingsnr)) {
        return { error: "Ondernemingsnummer moet formaat 0XXX.XXX.XXX volgen" };
    }

    const { data: entiteitData, error: entiteitErr } = await supabase
        .from("dim_legale_entiteit")
        .insert({
            owning_account_id: accountId,
            werkgeverscategorie,
            ondernemingsnr,
            naam,
            land_id: "BE",
            gewest,
        })
        .select("legale_entiteit_id")
        .single();

    if (entiteitErr || !entiteitData) {
        return { error: `Entiteit kon niet aangemaakt worden: ${entiteitErr?.message ?? "unknown"}` };
    }

    const { error: scenarioErr } = await supabase
        .from("dim_scenario")
        .insert({
            legale_entiteit_id: entiteitData.legale_entiteit_id,
            naam: "Baseline 2026",
            kind: "baseline",
        });

    if (scenarioErr) {
        // Compensating delete: entiteit zonder scenario is een half-af state.
        // User zou vast zitten op retry (unique constraint). Rollback zodat
        // hij opnieuw kan setup'en.
        const { error: rollbackErr } = await supabase
            .from("dim_legale_entiteit")
            .delete()
            .eq("legale_entiteit_id", entiteitData.legale_entiteit_id);
        if (rollbackErr) {
            console.error(
                "[setup] scenario faalde EN rollback faalde:",
                scenarioErr.message,
                rollbackErr.message,
            );
            return {
                error: `Setup faalde (${scenarioErr.message}) en cleanup mislukte (${rollbackErr.message}). Neem contact op met support.`,
            };
        }
        return {
            error: `Setup faalde bij baseline scenario: ${scenarioErr.message}. Je kunt opnieuw proberen.`,
        };
    }

    revalidatePath(`/dashboard/${accountSlug}`);
    redirect(`/dashboard/${accountSlug}?welcome=${encodeURIComponent(naam)}`);
}
