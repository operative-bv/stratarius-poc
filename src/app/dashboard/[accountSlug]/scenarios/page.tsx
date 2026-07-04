import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { FlaskConical, ArrowRight, Car } from "lucide-react";
import { redirect } from "next/navigation";
import Link from "next/link";

type Scenario = { scenario_id: string; naam: string; kind: string; created_at: string };
type Functie = { functie_id: string; functienaam: string };

export default async function ScenariosPage({
    params,
    searchParams,
}: {
    params: Promise<{ accountSlug: string }>;
    searchParams: Promise<{ created?: string; error?: string }>;
}) {
    const { accountSlug } = await params;
    const sp = await searchParams;
    const supabase = await createClient();

    const { data: entiteitData } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id, naam")
        .limit(1);
    const entiteit = entiteitData?.[0];

    const { data: scenariosData } = await supabase
        .from("dim_scenario")
        .select("scenario_id, naam, kind, created_at")
        .order("created_at", { ascending: false });
    const scenarios = (scenariosData ?? []) as Scenario[];
    const baseline = scenarios.find((s) => s.kind === "baseline");

    const { data: functiesData } = await supabase
        .from("dim_functie")
        .select("functie_id, functienaam")
        .order("functienaam");
    const functies = (functiesData ?? []) as Functie[];

    async function createScenario(formData: FormData) {
        "use server";
        const supabase = await createClient();
        const naam = String(formData.get("naam") ?? "").trim();
        const baselineId = String(formData.get("baseline") ?? "");
        const mutatieType = String(formData.get("mutatie_type") ?? "pct_increase");
        const mutatieValue = Number(formData.get("mutatie_value"));
        const teamId = String(formData.get("team") ?? "");
        const entiteitId = String(formData.get("entiteit") ?? "");

        if (!naam || !baselineId || !entiteitId || isNaN(mutatieValue)) {
            redirect(`/dashboard/${accountSlug}/scenarios?error=validation`);
        }

        const { data, error } = await supabase.rpc("create_what_if_scenario", {
            p_legale_entiteit_id: entiteitId,
            p_naam: naam,
            p_baseline_scenario_id: baselineId,
            p_periode: "2024-06-01",
            p_mutatie_type: mutatieType,
            p_mutatie_value: mutatieValue,
            p_functie_id: teamId === "all" ? null : teamId,
        });

        if (error) {
            redirect(`/dashboard/${accountSlug}/scenarios?error=${encodeURIComponent(error.message)}`);
        }
        redirect(`/dashboard/${accountSlug}/populatie?scenario=${data}&compare=1`);
    }

    async function createWagenScenario(formData: FormData) {
        "use server";
        const supabase = await createClient();
        const naam = String(formData.get("naam") ?? "").trim();
        const baselineId = String(formData.get("baseline") ?? "");
        const teamId = String(formData.get("team") ?? "");
        const wagenCat = String(formData.get("wagen_categorie") ?? "");
        const entiteitId = String(formData.get("entiteit") ?? "");

        if (!naam || !baselineId || !entiteitId || !teamId || !wagenCat) {
            redirect(`/dashboard/${accountSlug}/scenarios?error=validation`);
        }

        const { data, error } = await supabase.rpc("create_wagen_scenario", {
            p_legale_entiteit_id: entiteitId,
            p_naam: naam,
            p_baseline_scenario_id: baselineId,
            p_periode: "2024-06-01",
            p_functie_id: teamId,
            p_wagen_categorie: wagenCat,
        });

        if (error) {
            redirect(`/dashboard/${accountSlug}/scenarios?error=${encodeURIComponent(error.message)}`);
        }
        redirect(`/dashboard/${accountSlug}/populatie?scenario=${data}&compare=1`);
    }

    return (
        <div className="mx-auto max-w-5xl py-8 space-y-6">
            <div>
                <h1 className="text-3xl font-bold flex items-center gap-2">
                    <FlaskConical className="h-7 w-7" />
                    Scenario editor
                </h1>
                <p className="text-muted-foreground text-sm mt-1">
                    Maak een what-if scenario door baseline te kopiëren met een mutatie op basisloon
                </p>
            </div>

            {sp.error && (
                <Card>
                    <CardContent className="pt-6">
                        <p className="text-red-500 text-sm">Fout: {sp.error}</p>
                    </CardContent>
                </Card>
            )}

            <div className="grid gap-6 md:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle>Loon-mutatie scenario</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <form action={createScenario} className="space-y-4">
                            <input type="hidden" name="entiteit" value={entiteit?.legale_entiteit_id ?? ""} />

                            <div className="space-y-2">
                                <Label htmlFor="naam">Scenario naam</Label>
                                <Input id="naam" name="naam" placeholder="bv. Sales team krijgt bonus" required />
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="baseline">Baseline om te muteren</Label>
                                <Select name="baseline" defaultValue={baseline?.scenario_id}>
                                    <SelectTrigger id="baseline"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        {scenarios.map((s) => (
                                            <SelectItem key={s.scenario_id} value={s.scenario_id}>
                                                {s.naam}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="grid grid-cols-2 gap-3">
                                <div className="space-y-2">
                                    <Label htmlFor="mutatie_type">Mutatie type</Label>
                                    <Select name="mutatie_type" defaultValue="pct_increase">
                                        <SelectTrigger id="mutatie_type"><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                            <SelectItem value="pct_increase">Percentage (%)</SelectItem>
                                            <SelectItem value="flat_increase">Vast bedrag (+€)</SelectItem>
                                            <SelectItem value="flat_replace">Vervang basisloon (€)</SelectItem>
                                        </SelectContent>
                                    </Select>
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="mutatie_value">Waarde</Label>
                                    <Input id="mutatie_value" name="mutatie_value" type="number" step="0.01" placeholder="10" required />
                                </div>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="team">Toepassen op</Label>
                                <Select name="team" defaultValue="all">
                                    <SelectTrigger id="team"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="all">Alle medewerkers</SelectItem>
                                        {functies.map((f) => (
                                            <SelectItem key={f.functie_id} value={f.functie_id}>
                                                Alleen team {f.functienaam}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <Button type="submit" className="w-full">
                                Maak scenario → open in populatie
                            </Button>

                            <p className="text-xs text-muted-foreground">
                                Bij submit: nieuw scenario wordt aangemaakt, fact_looncomponent wordt gedupliceerd met mutatie, en je wordt geredirect naar populatie-view met vergelijk-modus.
                            </p>
                        </form>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Car className="h-5 w-5" />
                            Wagen-toewijzing scenario
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <form action={createWagenScenario} className="space-y-4">
                            <input type="hidden" name="entiteit" value={entiteit?.legale_entiteit_id ?? ""} />

                            <div className="space-y-2">
                                <Label htmlFor="wagen_naam">Scenario naam</Label>
                                <Input id="wagen_naam" name="naam" placeholder="bv. Sales team elektrische wagens" required />
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_baseline">Baseline</Label>
                                <Select name="baseline" defaultValue={baseline?.scenario_id}>
                                    <SelectTrigger id="wagen_baseline"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        {scenarios.filter((s) => s.kind === "baseline").map((s) => (
                                            <SelectItem key={s.scenario_id} value={s.scenario_id}>{s.naam}</SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_team">Team</Label>
                                <Select name="team" required>
                                    <SelectTrigger id="wagen_team"><SelectValue placeholder="Kies team" /></SelectTrigger>
                                    <SelectContent>
                                        {functies.map((f) => (
                                            <SelectItem key={f.functie_id} value={f.functie_id}>{f.functienaam}</SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_categorie">Wagen categorie</Label>
                                <Select name="wagen_categorie" defaultValue="electric">
                                    <SelectTrigger id="wagen_categorie"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="compact">Compact — €25k · €450/m · CO2 105</SelectItem>
                                        <SelectItem value="mid">Mid — €38k · €650/m · CO2 130</SelectItem>
                                        <SelectItem value="premium">Premium — €55k · €900/m · CO2 155</SelectItem>
                                        <SelectItem value="electric">Elektrisch — €45k · €700/m · CO2 0</SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>

                            <Button type="submit" className="w-full" variant="outline">
                                <Car className="h-4 w-4 mr-2" />
                                Maak wagen-scenario
                            </Button>

                            <p className="text-xs text-muted-foreground">
                                Voegt bedrijfswagen_tco (lease patronaal) + bedrijfswagen_vaa (fiscaal) toe voor elk contract in het gekozen team.
                            </p>
                        </form>
                    </CardContent>
                </Card>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle>Bestaande scenarios ({scenarios.length})</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="space-y-2">
                        {scenarios.map((s) => (
                            <Link
                                key={s.scenario_id}
                                href={`/dashboard/${accountSlug}/populatie?scenario=${s.scenario_id}&compare=1`}
                                className="flex items-center justify-between border rounded-lg p-3 hover:bg-muted/40 transition-colors group"
                            >
                                <div>
                                    <div className="text-sm font-medium flex items-center gap-2">
                                        {s.naam}
                                        <Badge variant={s.kind === "baseline" ? "outline" : "secondary"}>{s.kind}</Badge>
                                    </div>
                                    <div className="text-xs text-muted-foreground mt-1">
                                        {new Date(s.created_at).toLocaleString("nl-BE")}
                                    </div>
                                </div>
                                <ArrowRight className="h-4 w-4 text-muted-foreground group-hover:translate-x-1 transition-transform" />
                            </Link>
                        ))}
                    </div>
                </CardContent>
            </Card>
        </div>
    );
}
