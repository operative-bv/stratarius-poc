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

    // ISS-080: expliciet error check — silent drop verbergt RLS/timeout issues
    const { data: entData, error: entErr } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id")
        .limit(1);
    if (entErr) {
        return {
            ok: false,
            message: `Tenant lookup faalde: ${entErr.message}`,
            deletedContracten: null,
            deletedPersonen: null,
        };
    }
    const legaleEntiteitId = entData?.[0]?.legale_entiteit_id;
    if (!legaleEntiteitId) {
        return {
            ok: false,
            message: "Nog geen legale entiteit — voltooi eerst de setup wizard.",
            deletedContracten: null,
            deletedPersonen: null,
        };
    }

    const { data, error } = await supabase.rpc("clear_tenant_populatie", {
        p_legale_entiteit_id: legaleEntiteitId,
        p_rechtsgrondslag: "user reset via import page",
    });

    if (error) {
        return {
            ok: false,
            message: `Wissen faalde: ${error.message}`,
            deletedContracten: null,
            deletedPersonen: null,
        };
    }

    const row = (data ?? [])[0] as
        | {
              dim_contract_deleted: number;
              dim_persoon_deleted: number;
          }
        | undefined;

    revalidatePath(`/dashboard/${accountSlug}`);
    return {
        ok: true,
        message: "Populatie gewist.",
        deletedContracten: row?.dim_contract_deleted ?? 0,
        deletedPersonen: row?.dim_persoon_deleted ?? 0,
    };
}
