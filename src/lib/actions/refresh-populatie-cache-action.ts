"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { RefreshPopulatieCacheState } from "./refresh-populatie-cache-types";

export async function refreshPopulatieCacheAction(
    accountSlug: string,
    periode: string,
    scenarioId: string,
    _prev: RefreshPopulatieCacheState,
    _formData: FormData,
): Promise<RefreshPopulatieCacheState> {
    if (!scenarioId) {
        return { status: "error", message: "Scenario ontbreekt" };
    }
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("refresh_populatie_loonkost_cache", {
        p_periode: periode,
        p_scenario_id: scenarioId,
    });
    revalidatePath(`/dashboard/${accountSlug}/populatie`);
    if (error) {
        return { status: "error", message: `Cache refresh faalde: ${error.message}` };
    }
    return { status: "success", rowcount: (data as number) ?? 0 };
}
