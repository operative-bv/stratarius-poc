"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

export type RefreshMartState = {
    ok: boolean | null;
    message: string | null;
};

export const initialRefreshMartState: RefreshMartState = { ok: null, message: null };

export async function refreshMartAction(
    accountSlug: string,
    _prev: RefreshMartState,
    _formData: FormData,
): Promise<RefreshMartState> {
    const supabase = await createClient();
    const { error } = await supabase.rpc("refresh_mart_loonkloof", {
        p_rechtsgrondslag: "manual refresh via dashboard loonkloof page",
    });
    revalidatePath(`/dashboard/${accountSlug}/loonkloof`);
    if (error) {
        return { ok: false, message: `Refresh faalde: ${error.message}` };
    }
    return { ok: true, message: "Mart_loonkloof refreshed" };
}
