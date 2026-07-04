import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Users, TrendingUp, TrendingDown } from "lucide-react";
import {
    RowDetailSheet,
    type PopRow,
    type RSZParam,
    type StructureleParam,
    type ExtralegaalDetail,
} from "./row-detail-sheet";

type Scenario = { scenario_id: string; naam: string; kind: string };
type Functie = { functie_id: string; functienaam: string };

function roundFinal(value: number): string {
    const scaled = value * 100;
    const floor = Math.floor(scaled);
    const remainder = scaled - floor;
    let cents: number;
    if (Math.abs(remainder - 0.5) < 1e-9) {
        cents = floor % 2 === 0 ? floor : floor + 1;
    } else {
        cents = Math.round(scaled);
    }
    return (cents / 100).toLocaleString("nl-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function sum(rows: PopRow[], key: keyof PopRow): number {
    return rows.reduce((s, r) => s + Number(r[key]), 0);
}

export default async function PopulatiePage({
    searchParams,
}: {
    searchParams: Promise<{ periode?: string; scenario?: string; team?: string; compare?: string }>;
}) {
    const params = await searchParams;
    const periode = params.periode ?? "2024-06-01";
    const supabase = await createClient();

    // Load scenarios + teams (functies) voor dropdowns
    const { data: scenariosData } = await supabase
        .from("dim_scenario")
        .select("scenario_id, naam, kind")
        .order("kind", { ascending: true });
    const scenarios = (scenariosData ?? []) as Scenario[];
    const baseline = scenarios.find((s) => s.kind === "baseline");
    const scenarioId = params.scenario ?? baseline?.scenario_id ?? null;
    const activeScenario = scenarios.find((s) => s.scenario_id === scenarioId);

    const { data: functiesData } = await supabase
        .from("dim_functie")
        .select("functie_id, functienaam")
        .order("functienaam", { ascending: true });
    const functies = (functiesData ?? []) as Functie[];
    const teamId = params.team && params.team !== "all" ? params.team : null;
    const activeTeam = functies.find((f) => f.functie_id === teamId);

    // Load populatie snapshot voor actief scenario + team
    const { data, error } = await supabase.rpc("cascade_populatie_snapshot", {
        p_periode: periode,
        p_scenario_id: scenarioId,
        p_functie_id: teamId,
    });
    const rows = (data ?? []) as PopRow[];

    // Fetch tarieven voor drill-down dialog (RSZ + structurele vermindering actief op periode)
    const [{ data: rszData }, { data: structureleData }] = await Promise.all([
        supabase
            .from("param_rsz")
            .select("status, werkgeverscategorie, basisbijdrage_pct, basisfactor_arbeider_pct, bron_url, geldig_van, geldig_tot")
            .lte("geldig_van", periode)
            .or(`geldig_tot.is.null,geldig_tot.gt.${periode}`),
        supabase
            .from("param_structurele_vermindering")
            .select("werkgeverscategorie, forfait, coefficient_a, coefficient_b, bron_url, geldig_van, geldig_tot")
            .lte("geldig_van", periode)
            .or(`geldig_tot.is.null,geldig_tot.gt.${periode}`),
    ]);
    const rszParams = (rszData ?? []) as RSZParam[];
    const structureleParams = (structureleData ?? []) as StructureleParam[];

    // Fetch extralegaal componenten voor alle contracten in scope
    const contractIds = ((data ?? []) as PopRow[]).map((r) => r.contract_id);
    const extralegaalMap = new Map<string, ExtralegaalDetail[]>();
    if (contractIds.length > 0 && scenarioId) {
        const { data: extraData } = await supabase
            .from("fact_looncomponent")
            .select("contract_id, component_id, bedrag, bron_ref, dim_looncomponent!inner(name, familie, is_basisloon)")
            .in("contract_id", contractIds)
            .eq("periode", periode)
            .eq("scenario_id", scenarioId);
        for (const row of (extraData ?? []) as unknown as Array<{
            contract_id: string;
            component_id: string;
            bedrag: number;
            bron_ref: string | null;
            dim_looncomponent: { name: string; familie: string; is_basisloon: boolean };
        }>) {
            if (row.dim_looncomponent.is_basisloon) continue;
            if (row.dim_looncomponent.familie === "vakantiegeld") continue;
            const list = extralegaalMap.get(row.contract_id) ?? [];
            list.push({
                component_id: row.component_id,
                name: row.dim_looncomponent.name,
                bedrag: Number(row.bedrag),
                bron_ref: row.bron_ref,
            });
            extralegaalMap.set(row.contract_id, list);
        }
    }

    // Optional compare-baseline (zelfde team filter)
    let compareRows: PopRow[] = [];
    if (params.compare === "1" && baseline && scenarioId !== baseline.scenario_id) {
        const { data: compData } = await supabase.rpc("cascade_populatie_snapshot", {
            p_periode: periode,
            p_scenario_id: baseline.scenario_id,
            p_functie_id: teamId,
        });
        compareRows = (compData ?? []) as PopRow[];
    }

    const totals = {
        bruto: sum(rows, "bruto"),
        rsz: sum(rows, "stap2_basis_rsz"),
        verm: sum(rows, "stap3_vermindering"),
        bijz: sum(rows, "stap5_bijzondere"),
        vak: sum(rows, "stap6_vakantiegeld"),
        extra: sum(rows, "stap7_extralegaal"),
        pat: sum(rows, "totaal_patronale_kost"),
        tco: sum(rows, "tco"),
    };
    const compareTotals = compareRows.length > 0
        ? { bruto: sum(compareRows, "bruto"), pat: sum(compareRows, "totaal_patronale_kost"), tco: sum(compareRows, "tco") }
        : null;

    return (
        <div className="mx-auto max-w-7xl py-8 space-y-6">
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Users className="h-5 w-5" />
                        Populatie snapshot
                        <Badge variant="secondary">{rows.length} contracten</Badge>
                        {activeScenario && (
                            <Badge variant={activeScenario.kind === "baseline" ? "outline" : "default"}>
                                {activeScenario.naam}
                            </Badge>
                        )}
                        {activeTeam && (
                            <Badge variant="outline">Team: {activeTeam.functienaam}</Badge>
                        )}
                    </CardTitle>
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
                                            {s.naam} <span className="text-xs text-muted-foreground">({s.kind})</span>
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
                        <div className="space-y-2">
                            <Label htmlFor="periode">Periode</Label>
                            <Input id="periode" name="periode" type="date" defaultValue={periode} />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="compare" className="text-xs">Vergelijk met baseline</Label>
                            <div className="flex items-center h-9">
                                <input id="compare" name="compare" type="checkbox" value="1" defaultChecked={params.compare === "1"} className="h-4 w-4" />
                                <span className="ml-2 text-sm">Toon delta</span>
                            </div>
                        </div>
                        <Button type="submit">Herbereken</Button>
                    </form>
                </CardContent>
            </Card>

            {compareTotals && (
                <Card>
                    <CardContent className="pt-6">
                        <div className="grid grid-cols-3 gap-4">
                            <DeltaBox label="Δ Bruto (populatie)" baseline={compareTotals.bruto} current={totals.bruto} />
                            <DeltaBox label="Δ Patronale kost" baseline={compareTotals.pat} current={totals.pat} />
                            <DeltaBox label="Δ TCO totaal" baseline={compareTotals.tco} current={totals.tco} highlight />
                        </div>
                    </CardContent>
                </Card>
            )}

            {error && (
                <Card>
                    <CardContent className="pt-6"><p className="text-red-500">Error: {error.message}</p></CardContent>
                </Card>
            )}

            {rows.length > 0 && (
                <Card>
                    <CardContent className="pt-6 overflow-x-auto">
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Contract</TableHead>
                                    <TableHead>Team</TableHead>
                                    <TableHead>Status</TableHead>
                                    <TableHead>PC</TableHead>
                                    <TableHead className="text-right">Bruto</TableHead>
                                    <TableHead className="text-right">Basis RSZ</TableHead>
                                    <TableHead className="text-right text-green-600">Vermindering</TableHead>
                                    <TableHead className="text-right">Bijzondere</TableHead>
                                    <TableHead className="text-right">Vakantiegeld</TableHead>
                                    <TableHead className="text-right">Extralegaal</TableHead>
                                    <TableHead className="text-right font-semibold">Patronaal</TableHead>
                                    <TableHead className="text-right font-semibold">TCO</TableHead>
                                    <TableHead />
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {rows.map((r) => (
                                    <TableRow key={r.contract_id}>
                                        <TableCell className="font-mono text-xs">{r.contract_id.slice(0, 8)}</TableCell>
                                        <TableCell className="text-xs">{r.functienaam}</TableCell>
                                        <TableCell>
                                            <Badge variant={r.status === "arbeider" ? "outline" : "secondary"}>{r.status}</Badge>
                                        </TableCell>
                                        <TableCell>{r.pc_id}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {roundFinal(r.bruto)}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap2_basis_rsz)}</TableCell>
                                        <TableCell className="text-right tabular-nums text-green-600">−€ {roundFinal(r.stap3_vermindering)}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap5_bijzondere)}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap6_vakantiegeld)}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap7_extralegaal)}</TableCell>
                                        <TableCell className="text-right tabular-nums font-semibold">€ {roundFinal(r.totaal_patronale_kost)}</TableCell>
                                        <TableCell className="text-right tabular-nums font-semibold">€ {roundFinal(r.tco)}</TableCell>
                                        <TableCell className="text-right">
                                            <RowDetailSheet
                                                row={r}
                                                rszParams={rszParams}
                                                structureleParams={structureleParams}
                                                extralegaalDetails={extralegaalMap.get(r.contract_id) ?? []}
                                                periode={periode}
                                            />
                                        </TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                            <TableFooter>
                                <TableRow>
                                    <TableCell colSpan={4}>Totaal populatie ({rows.length})</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(totals.bruto)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(totals.rsz)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-green-600">−€ {roundFinal(totals.verm)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(totals.bijz)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(totals.vak)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(totals.extra)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-primary">€ {roundFinal(totals.pat)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-primary">€ {roundFinal(totals.tco)}</TableCell>
                                    <TableCell />
                                </TableRow>
                            </TableFooter>
                        </Table>
                        <p className="text-xs text-muted-foreground mt-4">
                            POC subset: exclusief stap 4 (doelgroepverminderingen), stap 8-9 (wagen, arbeidsongevallen). Bedragen via banker&apos;s rounding. RLS filtert automatisch op tenant.
                        </p>
                    </CardContent>
                </Card>
            )}

            {rows.length === 0 && !error && (
                <Card>
                    <CardContent className="pt-6">
                        <p className="text-muted-foreground">Geen contracten gevonden. Check scenario + periode filter.</p>
                    </CardContent>
                </Card>
            )}
        </div>
    );
}

function DeltaBox({ label, baseline, current, highlight = false }: { label: string; baseline: number; current: number; highlight?: boolean }) {
    const delta = current - baseline;
    const pct = baseline > 0 ? (delta / baseline) * 100 : 0;
    const isUp = delta >= 0;
    return (
        <div className={`rounded-lg border p-4 ${highlight ? "bg-secondary" : ""}`}>
            <div className="text-xs text-muted-foreground">{label}</div>
            <div className="text-2xl font-semibold mt-1 tabular-nums flex items-center gap-2">
                {isUp ? <TrendingUp className="h-5 w-5 text-orange-500" /> : <TrendingDown className="h-5 w-5 text-green-600" />}
                {isUp ? "+" : ""}€ {roundFinal(Math.abs(delta))}
            </div>
            <div className="text-xs text-muted-foreground mt-1">
                {isUp ? "+" : ""}{pct.toFixed(1)}% vs baseline (€ {roundFinal(baseline)})
            </div>
        </div>
    );
}
