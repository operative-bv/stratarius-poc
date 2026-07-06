import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { FlaskConical, ArrowRight } from "lucide-react";
import Link from "next/link";
import ScenariosTabs from "@/components/scenarios/scenarios-tabs";
import { PageHeader } from "@/components/dashboard/page-header";

type Scenario = { scenario_id: string; naam: string; kind: string; created_at: string };
type Functie = { functie_id: string; functienaam: string };

export default async function ScenariosPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    // ISS-098: resolve accountSlug naar account_id en filter alle tenant-queries
    // hierop. Zonder deze filter kon een multi-membership user scenarios/functies
    // van een andere tenant zien.
    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    const accountId = accountData?.account_id as string | undefined;

    const { data: entiteitData } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id, naam")
        .eq("owning_account_id", accountId ?? "")
        .limit(1);
    const entiteit = entiteitData?.[0];

    const { data: scenariosData } = accountId && entiteit
        ? await supabase
            .from("dim_scenario")
            .select("scenario_id, naam, kind, created_at, legale_entiteit_id, dim_legale_entiteit!inner(owning_account_id)")
            .eq("dim_legale_entiteit.owning_account_id", accountId)
            .order("created_at", { ascending: false })
        : { data: [] };
    const scenarios = (scenariosData ?? []) as Scenario[];
    const baseline = scenarios.find((s) => s.kind === "baseline");

    const { data: functiesData } = accountId
        ? await supabase
            .from("dim_functie")
            .select("functie_id, functienaam")
            .eq("owning_account_id", accountId)
            .order("functienaam")
        : { data: [] };
    const functies = (functiesData ?? []) as Functie[];

    return (
        <div className="space-y-6">
            <PageHeader
                icon={FlaskConical}
                title="Scenario editor"
                description="Maak een what-if scenario door baseline te kopiëren met een mutatie op basisloon of een wagen-toewijzing"
                actions={<Badge variant="secondary">{scenarios.length} scenarios</Badge>}
            />

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
