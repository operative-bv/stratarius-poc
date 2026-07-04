import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Building2, Info, Check } from "lucide-react";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

export default async function SetupPage({
    params,
    searchParams,
}: {
    params: Promise<{ accountSlug: string }>;
    searchParams: Promise<{ error?: string }>;
}) {
    const { accountSlug } = await params;
    const sp = await searchParams;
    const supabase = await createClient();

    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    if (!accountData) redirect("/dashboard");

    // Skip wizard als entiteit al bestaat
    const { data: existingEntiteit } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id")
        .eq("basejump_account_id", accountData.account_id)
        .limit(1);
    if (existingEntiteit && existingEntiteit.length > 0) {
        redirect(`/dashboard/${accountSlug}`);
    }

    async function completeSetup(formData: FormData) {
        "use server";
        const supabase = await createClient();
        const naam = String(formData.get("naam") ?? "").trim();
        const gewest = String(formData.get("gewest") ?? "vlaanderen");
        const werkgeverscategorie = Number(formData.get("werkgeverscategorie") ?? 1);
        const ondernemingsnr = String(formData.get("ondernemingsnr") ?? "").trim() || null;
        const accountId = String(formData.get("account_id") ?? "");

        if (!naam || !accountId) {
            redirect(`/dashboard/${accountSlug}/setup?error=${encodeURIComponent("Naam en account_id verplicht")}`);
        }

        // Belgische ondernemingsnr validatie (formaat 0XXX.XXX.XXX)
        if (ondernemingsnr && !/^[01]\d{3}\.\d{3}\.\d{3}$/.test(ondernemingsnr)) {
            redirect(`/dashboard/${accountSlug}/setup?error=${encodeURIComponent("Ondernemingsnummer moet formaat 0XXX.XXX.XXX volgen")}`);
        }

        const { data: entiteitData, error: entiteitErr } = await supabase
            .from("dim_legale_entiteit")
            .insert({
                basejump_account_id: accountId,
                werkgeverscategorie,
                ondernemingsnr,
                naam,
                land_id: "BE",
                gewest,
            })
            .select("legale_entiteit_id")
            .single();

        if (entiteitErr || !entiteitData) {
            redirect(`/dashboard/${accountSlug}/setup?error=${encodeURIComponent(`Entiteit kon niet aangemaakt worden: ${entiteitErr?.message ?? "unknown"}`)}`);
        }

        const { error: scenarioErr } = await supabase
            .from("dim_scenario")
            .insert({
                legale_entiteit_id: entiteitData.legale_entiteit_id,
                naam: "Baseline 2024",
                kind: "baseline",
            });

        if (scenarioErr) {
            redirect(`/dashboard/${accountSlug}/setup?error=${encodeURIComponent(`Entiteit aangemaakt maar baseline scenario faalde: ${scenarioErr.message}`)}`);
        }

        revalidatePath(`/dashboard/${accountSlug}`);
        redirect(`/dashboard/${accountSlug}?welcome=1`);
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

            {sp.error && (
                <Alert variant="destructive" className="mb-6">
                    <AlertTitle>Er ging iets mis</AlertTitle>
                    <AlertDescription>{sp.error}</AlertDescription>
                </Alert>
            )}

            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Building2 className="h-5 w-5" />
                        Organisatie configuratie
                    </CardTitle>
                    <CardDescription>
                        Deze gegevens sturen de rekencascade — je kunt ze later aanpassen via Settings.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <form action={completeSetup} className="space-y-5">
                        <input type="hidden" name="account_id" value={accountData.account_id} />

                        <div className="space-y-2">
                            <Label htmlFor="naam">Naam legale entiteit</Label>
                            <Input
                                id="naam"
                                name="naam"
                                defaultValue={accountData.name ?? ""}
                                placeholder="bv. Operative BVBA"
                                required
                            />
                            <p className="text-xs text-muted-foreground">
                                Verschijnt op facturen, rapporten en het dashboard. Vaak dezelfde naam als je organisatie.
                            </p>
                        </div>

                        <div className="grid gap-4 md:grid-cols-2">
                            <div className="space-y-2">
                                <Label htmlFor="gewest">Gewest</Label>
                                <Select name="gewest" defaultValue="vlaanderen">
                                    <SelectTrigger id="gewest"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="vlaanderen">Vlaanderen</SelectItem>
                                        <SelectItem value="brussel">Brussel-Hoofdstad</SelectItem>
                                        <SelectItem value="wallonie">Wallonië</SelectItem>
                                    </SelectContent>
                                </Select>
                                <p className="text-xs text-muted-foreground">
                                    Bepaalt welke doelgroepverminderingen (VDAB / Actiris / Forem) van toepassing zijn.
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="werkgeverscategorie">Werkgeverscategorie</Label>
                                <Select name="werkgeverscategorie" defaultValue="1">
                                    <SelectTrigger id="werkgeverscategorie"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="1">1 — Algemeen</SelectItem>
                                        <SelectItem value="2">2 — Social profit</SelectItem>
                                        <SelectItem value="3">3 — Beschutte werkplaats</SelectItem>
                                    </SelectContent>
                                </Select>
                                <p className="text-xs text-muted-foreground">
                                    Beïnvloedt RSZ-tarief (cat 1: 25.07% · cat 2: 24.32% · cat 3: 17.07%).
                                </p>
                            </div>
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="ondernemingsnr">Ondernemingsnummer (KBO) <span className="text-muted-foreground text-xs font-normal">— optioneel</span></Label>
                            <Input
                                id="ondernemingsnr"
                                name="ondernemingsnr"
                                placeholder="0123.456.789"
                                pattern="^[01]\d{3}\.\d{3}\.\d{3}$"
                            />
                            <p className="text-xs text-muted-foreground">
                                Formaat 0XXX.XXX.XXX. Nodig voor DmfA-aangifte en fiscaal rapporteren, niet voor de POC-berekeningen.
                            </p>
                        </div>

                        <Alert>
                            <Info className="h-4 w-4" />
                            <AlertTitle>Wat gebeurt hierna</AlertTitle>
                            <AlertDescription className="text-xs">
                                We maken een <code>dim_legale_entiteit</code> aan én een baseline scenario &quot;Baseline 2024&quot; waar al je contracten standaard onder vallen. Daarna kun je meteen contracten importeren via CSV of hand-in-hand toevoegen.
                            </AlertDescription>
                        </Alert>

                        <Button type="submit" className="w-full" size="lg">
                            <Check className="h-4 w-4 mr-2" />
                            Setup afronden en naar dashboard
                        </Button>
                    </form>
                </CardContent>
            </Card>

            <p className="text-xs text-muted-foreground text-center mt-6">
                Alleen deze eerste keer nodig · Wijzigingen later via Settings → Organisatie
            </p>
        </div>
    );
}
