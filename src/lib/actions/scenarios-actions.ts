"use server";

import { createClient } from "@/lib/supabase/server";
import { initialScenarioState, type ScenarioState } from "./scenarios-types";

export async function createScenarioAction(
    accountSlug: string,
    _prev: ScenarioState,
    formData: FormData,
): Promise<ScenarioState> {
    const supabase = await createClient();
    const naam = String(formData.get("naam") ?? "").trim();
    const baselineId = String(formData.get("baseline") ?? "");
    const mutatieType = String(formData.get("mutatie_type") ?? "pct_increase");
    const mutatieValue = Number(formData.get("mutatie_value"));
    const teamId = String(formData.get("team") ?? "");
    const entiteitId = String(formData.get("entiteit") ?? "");

    if (!naam || !baselineId || !entiteitId || isNaN(mutatieValue)) {
        return { ...initialScenarioState, error: "Vul alle verplichte velden in" };
    }

    const { data, error } = await supabase.rpc("create_what_if_scenario", {
        p_legale_entiteit_id: entiteitId,
        p_naam: naam,
        p_baseline_scenario_id: baselineId,
        p_periode: "2026-06-01",
        p_mutatie_type: mutatieType,
        p_mutatie_value: mutatieValue,
        p_functie_id: teamId === "all" ? null : teamId,
    });

    if (error) {
        return { ...initialScenarioState, error: error.message };
    }

    return {
        error: null,
        redirectTo: `/dashboard/${accountSlug}/populatie?scenario=${data}&compare=1`,
        successMessage: `Scenario "${naam}" aangemaakt`,
    };
}

export async function createWagenScenarioAction(
    accountSlug: string,
    _prev: ScenarioState,
    formData: FormData,
): Promise<ScenarioState> {
    const supabase = await createClient();
    const naam = String(formData.get("naam") ?? "").trim();
    const baselineId = String(formData.get("baseline") ?? "");
    const teamId = String(formData.get("team") ?? "");
    const wagenCat = String(formData.get("wagen_categorie") ?? "");
    const entiteitId = String(formData.get("entiteit") ?? "");

    if (!naam || !baselineId || !entiteitId || !teamId || !wagenCat) {
        return { ...initialScenarioState, error: "Vul alle verplichte velden in" };
    }

    const { data, error } = await supabase.rpc("create_wagen_scenario", {
        p_legale_entiteit_id: entiteitId,
        p_naam: naam,
        p_baseline_scenario_id: baselineId,
        p_periode: "2026-06-01",
        p_functie_id: teamId,
        p_wagen_categorie: wagenCat,
    });

    if (error) {
        return { ...initialScenarioState, error: error.message };
    }

    return {
        error: null,
        redirectTo: `/dashboard/${accountSlug}/populatie?scenario=${data}&compare=1`,
        successMessage: `Wagen-scenario "${naam}" aangemaakt`,
    };
}
