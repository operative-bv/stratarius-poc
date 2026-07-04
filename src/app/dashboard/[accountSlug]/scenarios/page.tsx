import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { FlaskConical, ArrowRight } from "lucide-react";
import Link from "next/link";
import ScenariosTabs from "@/components/scenarios/scenarios-tabs";

type Scenario = { scenario_id: string; naam: string; kind: string; created_at: string };
type Functie = { functie_id: string; functienaam: string };

export default async function ScenariosPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
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

            <ScenariosTabs
                accountSlug={accountSlug}
                entiteitId={entiteit?.legale_entiteit_id ?? ""}
                baselineId={baseline?.scenario_id}
                scenarios={scenarios}
                functies={functies}
            />

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
