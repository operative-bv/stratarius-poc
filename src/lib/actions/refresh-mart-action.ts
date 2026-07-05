"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { RefreshMartState } from "./refresh-mart-types";

export async function refreshMartAction(
    accountSlug: string,
    _prev: RefreshMartState,
    _formData: FormData,
): Promise<RefreshMartState> {
    const supabase = await createClient();
    const { error } = await supabase.rpc("refresh_mart_loonkloof", {
        p_rechtsgrondslag: "manual refresh via dashboard loonkloof page",
    });
    // ISS-080 note: revalidate ook bij error zodat een volgend bezoek verse
    // data probeert op te halen (cache blijft anders potentially stale).
    revalidatePath(`/dashboard/${accountSlug}/loonkloof`);
    if (error) {
        return { status: "error", message: `Refresh faalde: ${error.message}` };
    }
    return { status: "success", message: "Mart_loonkloof refreshed" };
}
