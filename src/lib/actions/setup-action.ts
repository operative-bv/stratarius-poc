"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { SetupState } from "./setup-types";

export async function completeSetupAction(
    accountSlug: string,
    _prev: SetupState,
    formData: FormData,
): Promise<SetupState> {
    const supabase = await createClient();

    const naam = String(formData.get("naam") ?? "").trim();
    const gewest = String(formData.get("gewest") ?? "vlaanderen");
    const werkgeverscategorie = Number(formData.get("werkgeverscategorie") ?? 1);
    const ondernemingsnr = String(formData.get("ondernemingsnr") ?? "").trim() || null;
    const accountId = String(formData.get("account_id") ?? "");

    if (!naam || !accountId) {
        return { error: "Naam en account_id verplicht" };
    }

    if (ondernemingsnr && !/^[01]\d{3}\.\d{3}\.\d{3}$/.test(ondernemingsnr)) {
        return { error: "Ondernemingsnummer moet formaat 0XXX.XXX.XXX volgen" };
    }

    // ISS-096: atomische setup via SECURITY DEFINER RPC — vervangt de oude
    // direct-insert + compensating-delete pattern. Entiteit + baseline
    // scenario worden in één transactie aangemaakt.
    const { error: setupErr } = await supabase.rpc("complete_tenant_setup", {
        p_owning_account_id: accountId,
        p_naam: naam,
        p_gewest: gewest,
        p_werkgeverscategorie: werkgeverscategorie,
        p_ondernemingsnr: ondernemingsnr,
    });

    if (setupErr) {
        return { error: `Setup faalde: ${setupErr.message}` };
    }

    revalidatePath(`/dashboard/${accountSlug}`);
    redirect(`/dashboard/${accountSlug}?welcome=${encodeURIComponent(naam)}`);
}
