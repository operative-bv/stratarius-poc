import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DatePicker } from "@/components/ui/date-picker";
import { Checkbox } from "@/components/ui/checkbox";
import { Users, Info } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { PageHeader } from "@/components/dashboard/page-header";
import PopulatieResults from "./populatie-results";
import PopulatieSkeleton from "./populatie-skeleton";

type Scenario = { scenario_id: string; naam: string; kind: string };
type Functie = { functie_id: string; functienaam: string };

export default async function PopulatiePage({
    params: routeParams,
    searchParams,
}: {
    params: Promise<{ accountSlug: string }>;
    searchParams: Promise<{ periode?: string; scenario?: string; team?: string; compare?: string; view?: string }>;
}) {
    const { accountSlug } = await routeParams;
    const params = await searchParams;
    const periode = params.periode ?? "2026-06-01";
    const view = params.view === "jaar" ? "jaar" : "maand";
    const factor = view === "jaar" ? 12 : 1;
    const supabase = await createClient();

    // ISS-098: resolve accountSlug naar account_id en filter alle tenant-queries
    // hierop. Zonder deze filter kon een multi-membership user scenarios/functies
    // van een andere tenant zien in de filter-dropdowns.
    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    const accountId = accountData?.account_id as string | undefined;

    // Snelle metadata queries — renderen direct in de shell
    const [{ data: scenariosData }, { data: functiesData }] = accountId
        ? await Promise.all([
            supabase
                .from("dim_scenario")
                .select("scenario_id, naam, kind, legale_entiteit_id, dim_legale_entiteit!inner(owning_account_id)")
                .eq("dim_legale_entiteit.owning_account_id", accountId)
                .order("kind", { ascending: true }),
            supabase
                .from("dim_functie")
                .select("functie_id, functienaam")
                .eq("owning_account_id", accountId)
                .order("functienaam", { ascending: true }),
        ])
        : [{ data: [] }, { data: [] }];
    const scenarios = (scenariosData ?? []) as Scenario[];
    const functies = (functiesData ?? []) as Functie[];
    const baseline = scenarios.find((s) => s.kind === "baseline");
    const scenarioId = params.scenario ?? baseline?.scenario_id ?? null;
    const activeScenario = scenarios.find((s) => s.scenario_id === scenarioId);
    const teamId = params.team && params.team !== "all" ? params.team : null;
    const activeTeam = functies.find((f) => f.functie_id === teamId);

    // Suspense key zorgt dat filter-changes een nieuwe boundary triggeren
    const suspenseKey = `${periode}-${scenarioId}-${teamId}-${params.compare ?? ""}-${view}`;

    return (
        <div className="space-y-6">
            <PageHeader
                icon={Users}
                title="Populatie snapshot"
                description={`Rekencascade voor periode ${periode}`}
                actions={
                    <div className="flex flex-wrap items-center gap-2">
                        {activeScenario && (
                            <Badge variant={activeScenario.kind === "baseline" ? "outline" : "default"}>
                                {activeScenario.naam}
                            </Badge>
                        )}
                        {activeTeam && <Badge variant="outline">Team: {activeTeam.functienaam}</Badge>}
                    </div>
                }
            />

            <Card>
                <CardHeader>
                    <CardTitle className="text-base">Filters</CardTitle>
                </CardHeader>
                <CardContent>
                    <form className="flex items-end gap-3 flex-wrap" method="get">
                        <div className="space-y-2 min-w-[180px]">
                            <Label htmlFor="scenario">Scenario</Label>
                            <Select name="scenario" defaultValue={scenarioId ?? undefined}>
                                <SelectTrigger id="scenario"><SelectValue placeholder="Selecteer scenario" /></SelectTrigger>
                                <SelectContent>
                                    {scenarios.map((s) => (
                                        <SelectItem key={s.scenario_id} value={s.scenario_id}>
                                            {s.naam}{" "}
                                            <span className="text-xs text-muted-foreground">({s.kind})</span>
                                        </SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2 min-w-[160px]">
                            <Label htmlFor="team">Team</Label>
                            <Select name="team" defaultValue={teamId ?? "all"}>
                                <SelectTrigger id="team"><SelectValue /></SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="all">Alle teams</SelectItem>
                                    {functies.map((f) => (
                                        <SelectItem key={f.functie_id} value={f.functie_id}>
                                            {f.functienaam}
                                        </SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2 min-w-[200px]">
                            <Label htmlFor="periode">Periode</Label>
                            <DatePicker id="periode" name="periode" defaultValue={periode} />
                        </div>
                        <div className="space-y-2 min-w-[140px]">
                            <Label htmlFor="view" className="flex items-center gap-1">
                                Weergave
                                <TooltipProvider>
                                    <Tooltip>
                                        <TooltipTrigger asChild>
                                            <Info className="h-3 w-3 text-muted-foreground cursor-help" />
                                        </TooltipTrigger>
                                        <TooltipContent side="top" className="max-w-xs">
                                            <p className="text-xs">
                                                <strong>Maand</strong>: cascade-accrual voor de gekozen datum.
                                                <br />
                                                <strong>Jaar</strong>: 12 × maand-accrual. Aanname: heel jaar hetzelfde contract.
                                            </p>
                                        </TooltipContent>
                                    </Tooltip>
                                </TooltipProvider>
                            </Label>
                            <Select name="view" defaultValue={view}>
                                <SelectTrigger id="view"><SelectValue /></SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="maand">Maandkost</SelectItem>
                                    <SelectItem value="jaar">Jaarkost (× 12)</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="flex flex-col gap-2">
                            <Label htmlFor="compare" className="text-xs">
                                Vergelijk met baseline
                            </Label>
                            <div className="flex items-center h-9 gap-2">
                                <Checkbox
                                    id="compare"
                                    name="compare"
                                    value="1"
                                    defaultChecked={params.compare === "1"}
                                />
                                <Label htmlFor="compare" className="text-sm font-normal">
                                    Toon delta
                                </Label>
                            </div>
                        </div>
                        <Button type="submit">Herbereken</Button>
                    </form>
                </CardContent>
            </Card>


            <Suspense key={suspenseKey} fallback={<PopulatieSkeleton />}>
                <PopulatieResults
                    periode={periode}
                    scenarioId={scenarioId}
                    baselineScenarioId={baseline?.scenario_id ?? null}
                    teamId={teamId}
                    compare={params.compare === "1"}
                    view={view}
                    factor={factor}
                />
            </Suspense>
        </div>
    );
}
