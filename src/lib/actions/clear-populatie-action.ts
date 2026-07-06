"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { ClearPopulatieState } from "./clear-populatie-types";

export async function clearPopulatieAction(
    accountSlug: string,
    _prev: ClearPopulatieState,
    _formData: FormData,
): Promise<ClearPopulatieState> {
    const supabase = await createClient();

    const { data: entData, error: entErr } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id")
        .limit(1);
    if (entErr) {
        return { status: "error", message: `Tenant lookup faalde: ${entErr.message}` };
    }
    const legaleEntiteitId = entData?.[0]?.legale_entiteit_id;
    if (!legaleEntiteitId) {
        return {
            status: "error",
            message: "Nog geen legale entiteit — voltooi eerst de setup wizard.",
        };
    }

    const { data, error } = await supabase.rpc("clear_tenant_populatie", {
        p_legale_entiteit_id: legaleEntiteitId,
    });

    if (error) {
        return { status: "error", message: `Wissen faalde: ${error.message}` };
    }

    const row = (data ?? [])[0] as
        | { deleted_contracten: number; deleted_personen: number }
        | undefined;

    revalidatePath(`/dashboard/${accountSlug}`);
    return {
        status: "success",
        deletedContracten: row?.deleted_contracten ?? 0,
        deletedPersonen: row?.deleted_personen ?? 0,
    };
}
