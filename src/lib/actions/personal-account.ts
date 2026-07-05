"use server";

import { createClient } from "../supabase/server";
import { revalidatePath } from "next/cache";

export async function editPersonalAccountName(_prevState: unknown, formData: FormData) {
    const name = formData.get("name") as string;
    const accountId = formData.get("accountId") as string;
    const supabase = await createClient();

    const { error } = await supabase.rpc("update_account", {
        name,
        account_id: accountId,
    });

    if (error) {
        return { message: error.message };
    }

    // Revalidate hele dashboard layout tree — sidebar (TeamSwitcher +
    // UserAccountButton) rendert vanuit de layout die de account naam
    // ophaalt. Zonder revalidate blijft cached layout de oude naam tonen.
    revalidatePath("/dashboard", "layout");
    return { message: null };
}
