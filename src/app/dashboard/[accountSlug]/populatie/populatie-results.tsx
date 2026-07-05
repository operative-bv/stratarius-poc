import { createClient } from "@/lib/supabase/server";
import { roundFinal as roundFinalMirror } from "@/lib/cascade-mirror";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { TrendingUp, TrendingDown } from "lucide-react";
import {
    RowDetailSheet,
    type PopRow,
    type RSZParam,
    type StructureleParam,
    type ExtralegaalDetail,
} from "./row-detail-sheet";

const roundFinal = (v: number) => roundFinalMirror(v);

function sum(rows: PopRow[], key: keyof PopRow): number {
    return rows.reduce((s, r) => s + Number(r[key]), 0);
}

export default async function PopulatieResults({
    periode,
    scenarioId,
    baselineScenarioId,
    teamId,
    compare,
    view,
    factor,
}: {
    periode: string;
    scenarioId: string | null;
    baselineScenarioId: string | null;
    teamId: string | null;
    compare: boolean;
    view: "maand" | "jaar";
    factor: number;
}) {
    const supabase = await createClient();
    const filters = teamId ? { functie_ids: [teamId] } : {};

    const { data, error } = await supabase.rpc("cascade_populatie_snapshot", {
        p_periode: periode,
        p_scenario_id: scenarioId,
        p_filters: filters,
    });
    const rows = (data ?? []) as PopRow[];

    // ISS-080: expliciete error propagation ipv `?? []` fallbacks. Als de
    // param queries falen zou RowDetailSheet renderen met lege drempels
    // ("berekening loopt niet") wat verwarrend is.
    const [rszRes, structureleRes] = await Promise.all([
        supabase
            .from("param_rsz")
            .select("status, werkgeverscategorie, basisbijdrage_pct, basisfactor_pct, bron_url, geldig_van, geldig_tot")
            .lte("geldig_van", periode)
            .or(`geldig_tot.is.null,geldig_tot.gt.${periode}`),
        supabase
            .from("param_structurele_vermindering")
            .select("werkgeverscategorie, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url, geldig_van, geldig_tot")
            .lte("geldig_van", periode)
            .or(`geldig_tot.is.null,geldig_tot.gt.${periode}`),
    ]);
    if (rszRes.error) console.error("[populatie-results] param_rsz:", rszRes.error);
    if (structureleRes.error) console.error("[populatie-results] param_structurele:", structureleRes.error);
    const rszParams = (rszRes.data ?? []) as RSZParam[];
    const structureleParams = (structureleRes.data ?? []) as StructureleParam[];

    const contractIds = rows.map((r) => r.contract_id);
    const extralegaalMap = new Map<string, ExtralegaalDetail[]>();
    if (contractIds.length > 0 && scenarioId) {
        const { data: extraData, error: extraErr } = await supabase
            .from("fact_looncomponent")
            .select("contract_id, component_id, bedrag, bron_ref, dim_looncomponent!inner(name, familie, is_basisloon)")
            .in("contract_id", contractIds)
            .eq("periode", periode)
            .eq("scenario_id", scenarioId);
        if (extraErr) console.error("[populatie-results] extralegaal fetch:", extraErr);
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

    let compareRows: PopRow[] = [];
    if (compare && baselineScenarioId && scenarioId !== baselineScenarioId) {
        const { data: compData, error: compErr } = await supabase.rpc("cascade_populatie_snapshot", {
            p_periode: periode,
            p_scenario_id: baselineScenarioId,
            p_filters: filters,
        });
        if (compErr) console.error("[populatie-results] compare snapshot:", compErr);
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
    const compareTotals =
        compareRows.length > 0
            ? {
                  bruto: sum(compareRows, "bruto"),
                  pat: sum(compareRows, "totaal_patronale_kost"),
                  tco: sum(compareRows, "tco"),
              }
            : null;

    if (error) {
        return (
            <Card>
                <CardContent className="pt-6">
                    <p className="text-red-500">Error: {error.message}</p>
                </CardContent>
            </Card>
        );
    }

    if (rows.length === 0) {
        return (
            <Card>
                <CardContent className="pt-6">
                    <p className="text-muted-foreground">Geen contracten gevonden. Check scenario + periode filter.</p>
                </CardContent>
            </Card>
        );
    }

    return (
        <>
            {compareTotals && (
                <Card>
                    <CardContent className="pt-6">
                        <div className="grid grid-cols-3 gap-4">
                            <DeltaBox
                                label={`Δ Bruto (populatie, ${view})`}
                                baseline={compareTotals.bruto * factor}
                                current={totals.bruto * factor}
                            />
                            <DeltaBox
                                label={`Δ Patronale kost (${view})`}
                                baseline={compareTotals.pat * factor}
                                current={totals.pat * factor}
                            />
                            <DeltaBox
                                label={`Δ TCO totaal (${view})`}
                                baseline={compareTotals.tco * factor}
                                current={totals.tco * factor}
                                highlight
                            />
                        </div>
                    </CardContent>
                </Card>
            )}

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
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(r.bruto * factor)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap2_basis_rsz * factor)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-green-600">
                                        −€ {roundFinal(r.stap3_vermindering * factor)}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap5_bijzondere * factor)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap6_vakantiegeld * factor)}</TableCell>
                                    <TableCell className="text-right tabular-nums">€ {roundFinal(r.stap7_extralegaal * factor)}</TableCell>
                                    <TableCell className="text-right tabular-nums font-semibold">
                                        € {roundFinal(r.totaal_patronale_kost * factor)}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums font-semibold">
                                        € {roundFinal(r.tco * factor)}
                                    </TableCell>
                                    <TableCell className="text-right">
                                        <RowDetailSheet
                                            row={r}
                                            rszParams={rszParams}
                                            structureleParams={structureleParams}
                                            extralegaalDetails={extralegaalMap.get(r.contract_id) ?? []}
                                            periode={periode}
                                            viewMode={view}
                                        />
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                        <TableFooter>
                            <TableRow>
                                <TableCell colSpan={4}>
                                    Totaal populatie ({rows.length}) — {view === "jaar" ? "jaarbasis" : "maandbasis"}
                                </TableCell>
                                <TableCell className="text-right tabular-nums">€ {roundFinal(totals.bruto * factor)}</TableCell>
                                <TableCell className="text-right tabular-nums">€ {roundFinal(totals.rsz * factor)}</TableCell>
                                <TableCell className="text-right tabular-nums text-green-600">
                                    −€ {roundFinal(totals.verm * factor)}
                                </TableCell>
                                <TableCell className="text-right tabular-nums">€ {roundFinal(totals.bijz * factor)}</TableCell>
                                <TableCell className="text-right tabular-nums">€ {roundFinal(totals.vak * factor)}</TableCell>
                                <TableCell className="text-right tabular-nums">€ {roundFinal(totals.extra * factor)}</TableCell>
                                <TableCell className="text-right tabular-nums text-primary">
                                    € {roundFinal(totals.pat * factor)}
                                </TableCell>
                                <TableCell className="text-right tabular-nums text-primary">
                                    € {roundFinal(totals.tco * factor)}
                                </TableCell>
                                <TableCell />
                            </TableRow>
                        </TableFooter>
                    </Table>
                    <p className="text-xs text-muted-foreground mt-4">
                        Cascade 9 stappen actief inclusief stap 4 doelgroepverminderingen (non-cumulatie), stap 8 wagen
                        CO2-solidariteitsbijdrage, stap 9 arbeidsongevallen. Bedragen via banker&apos;s rounding. RLS filtert
                        automatisch op tenant.
                    </p>
                </CardContent>
            </Card>
        </>
    );
}

function DeltaBox({
    label,
    baseline,
    current,
    highlight = false,
}: {
    label: string;
    baseline: number;
    current: number;
    highlight?: boolean;
}) {
    const delta = current - baseline;
    const pct = baseline > 0 ? (delta / baseline) * 100 : 0;
    const isUp = delta >= 0;
    return (
        <div className={`rounded-lg border p-4 ${highlight ? "bg-secondary" : ""}`}>
            <div className="text-xs text-muted-foreground">{label}</div>
            <div className="text-2xl font-semibold mt-1 tabular-nums flex items-center gap-2">
                {isUp ? (
                    <TrendingUp className="h-5 w-5 text-orange-500" />
                ) : (
                    <TrendingDown className="h-5 w-5 text-green-600" />
                )}
                {isUp ? "+" : ""}€ {roundFinal(Math.abs(delta))}
            </div>
            <div className="text-xs text-muted-foreground mt-1">
                {isUp ? "+" : ""}
                {pct.toFixed(1)}% vs baseline (€ {roundFinal(baseline)})
            </div>
        </div>
    );
}
