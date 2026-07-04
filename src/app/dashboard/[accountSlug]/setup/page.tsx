import { createClient } from "@/lib/supabase/server";
import { Progress } from "@/components/ui/progress";
import { Building2 } from "lucide-react";
import { redirect } from "next/navigation";
import SetupForm from "@/components/setup/setup-form";

export default async function SetupPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    if (!accountData) redirect("/dashboard");

    const { data: existingEntiteit } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id")
        .eq("owning_account_id", accountData.account_id)
        .limit(1);
    if (existingEntiteit && existingEntiteit.length > 0) {
        redirect(`/dashboard/${accountSlug}`);
    }

    return (
        <div className="mx-auto max-w-2xl py-12 px-4">
            <div className="text-center mb-8">
                <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-primary/10 mb-4">
                    <Building2 className="h-6 w-6 text-primary" />
                </div>
                <h1 className="text-3xl font-bold">Welkom bij Stratarius</h1>
                <p className="text-muted-foreground mt-2">
                    Nog één stap: vertel ons over je Belgische legale entiteit. Dit bepaalt welke RSZ-tarieven, doelgroepverminderingen en cascade-parameters gebruikt worden.
                </p>
            </div>

            <div className="mb-6">
                <div className="flex items-center justify-between text-xs text-muted-foreground mb-2">
                    <span>Configuratie</span>
                    <span>Stap 1 van 1</span>
                </div>
                <Progress value={50} className="h-2" />
            </div>

            <SetupForm
                accountSlug={accountSlug}
                accountId={accountData.account_id}
                defaultNaam={accountData.name ?? ""}
            />

            <p className="text-xs text-muted-foreground text-center mt-6">
                Alleen deze eerste keer nodig · Wijzigingen later via Settings → Organisatie
            </p>
        </div>
    );
}
