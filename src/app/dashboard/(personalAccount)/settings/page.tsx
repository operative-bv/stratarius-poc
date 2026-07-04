import EditPersonalAccountName from "@/components/basejump/edit-personal-account-name";
import AccountInfoCard from "@/components/account/account-info-card";
import ChangePasswordCard from "@/components/account/change-password-card";
import SessionsCard from "@/components/account/sessions-card";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/server";

export default async function PersonalAccountSettingsPage({
    searchParams,
}: {
    searchParams: { kind?: string; message?: string };
}) {
    const supabaseClient = createClient();
    const { data: personalAccount } = await supabaseClient.rpc("get_personal_account");

    return (
        <div className="flex flex-col gap-y-6">
            {searchParams?.kind === "password_ok" && (
                <Alert className="border-emerald-500/40 bg-emerald-500/5">
                    <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    <AlertTitle>Wachtwoord gewijzigd</AlertTitle>
                    <AlertDescription>Je nieuwe wachtwoord is actief.</AlertDescription>
                </Alert>
            )}
            {searchParams?.kind === "password_error" && (
                <Alert variant="destructive">
                    <AlertTriangle className="h-4 w-4" />
                    <AlertTitle>Wachtwoord niet gewijzigd</AlertTitle>
                    <AlertDescription>{searchParams.message ?? "Onbekende fout"}</AlertDescription>
                </Alert>
            )}
            {searchParams?.kind === "sessions_ok" && (
                <Alert className="border-emerald-500/40 bg-emerald-500/5">
                    <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    <AlertTitle>Uitgelogd op andere apparaten</AlertTitle>
                    <AlertDescription>
                        Alle andere sessies zijn beëindigd. Je huidige sessie blijft actief.
                    </AlertDescription>
                </Alert>
            )}
            {searchParams?.kind === "sessions_error" && (
                <Alert variant="destructive">
                    <AlertTriangle className="h-4 w-4" />
                    <AlertTitle>Uitloggen mislukt</AlertTitle>
                    <AlertDescription>{searchParams.message ?? "Onbekende fout"}</AlertDescription>
                </Alert>
            )}

            <EditPersonalAccountName account={personalAccount} />
            <AccountInfoCard />
            <ChangePasswordCard />
            <SessionsCard />
        </div>
    );
}
