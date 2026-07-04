"use server";

import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

/**
 * Change password voor de ingelogde user.
 * Supabase `auth.updateUser({ password })` is de canonieke API.
 * User moet ingelogd zijn (session cookie geldig).
 */
export async function changePassword(_prevState: unknown, formData: FormData) {
    const password = String(formData.get("password") ?? "");
    const confirm = String(formData.get("confirm") ?? "");

    if (!password || password.length < 8) {
        return redirect(
            "/dashboard/settings?message=" +
                encodeURIComponent("Wachtwoord moet minstens 8 tekens zijn") +
                "&kind=password_error",
        );
    }
    if (password !== confirm) {
        return redirect(
            "/dashboard/settings?message=" +
                encodeURIComponent("Wachtwoorden komen niet overeen") +
                "&kind=password_error",
        );
    }

    const supabase = createClient();
    const { error } = await supabase.auth.updateUser({ password });

    if (error) {
        return redirect(
            "/dashboard/settings?message=" +
                encodeURIComponent(error.message) +
                "&kind=password_error",
        );
    }

    return redirect("/dashboard/settings?kind=password_ok");
}

/**
 * Sign out van ALLE andere sessies (behoudt huidige).
 * Supabase `auth.signOut({ scope: 'others' })` invalidateert refresh tokens
 * voor alle andere devices; huidige session blijft actief.
 */
export async function signOutOtherSessions() {
    const supabase = createClient();
    const { error } = await supabase.auth.signOut({ scope: "others" });

    if (error) {
        return redirect(
            "/dashboard/settings?message=" +
                encodeURIComponent(error.message) +
                "&kind=sessions_error",
        );
    }
    return redirect("/dashboard/settings?kind=sessions_ok");
}
