"use server";

import { createClient } from "@/lib/supabase/server";
import type { AccountActionState } from "./account-security-types";

export async function changePassword(
    _prev: AccountActionState,
    formData: FormData,
): Promise<AccountActionState> {
    const password = String(formData.get("password") ?? "");
    const confirm = String(formData.get("confirm") ?? "");

    if (!password || password.length < 8) {
        return { ok: false, message: "Wachtwoord moet minstens 8 tekens zijn" };
    }
    if (password !== confirm) {
        return { ok: false, message: "Wachtwoorden komen niet overeen" };
    }

    const supabase = await createClient();
    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
        return { ok: false, message: error.message };
    }
    return { ok: true, message: "Wachtwoord bijgewerkt" };
}

export async function signOutOtherSessions(
    _prev: AccountActionState,
    _formData: FormData,
): Promise<AccountActionState> {
    const supabase = await createClient();
    const { error } = await supabase.auth.signOut({ scope: "others" });
    if (error) {
        return { ok: false, message: error.message };
    }
    return { ok: true, message: "Alle andere sessies zijn uitgelogd" };
}
