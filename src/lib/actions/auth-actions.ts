"use server";

import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export async function signOutAction() {
    // ISS-080: sign-out kan falen (network, revoked session, etc). Bij falen
    // is de session mogelijk NOG valid op server-side → security-relevant om
    // dit expliciet te loggen. Redirect gebeurt hoe dan ook (user intent is
    // "ik wil weg") maar we hebben nu de log spoor voor debugging.
    const supabase = await createClient();
    const { error } = await supabase.auth.signOut();
    if (error) {
        console.error("[signOut] Supabase error:", error.status, error.code, error.message);
    }
    redirect("/");
}
