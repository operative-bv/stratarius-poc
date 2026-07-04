import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Scale, TrendingUp, TrendingDown, Minus, RefreshCw, SplitSquareHorizontal } from "lucide-react";
import { revalidatePath } from "next/cache";

type MartRow = {
    persoon_id: string;
    referentiedatum: string;
    kwartaal: string;
    uurloon_bruto: number;
    basis_vte: number;
    variabele_vte: number;
    geslacht: string;
    functieniveau: number;
    ancienniteit_jaren: number;
};

type DecompRow = {
    legale_entiteit_id: string;
    referentiedatum: string;
    kwartaal: string;
    n_m: number;
    n_v: number;
    gem_uurloon_m: number;
    gem_uurloon_v: number;
    raw_gap: number;
    residual_gap: number;
    endowment_gap: number;
    raw_gap_ci95_halfwidth: number;
    matched_stratum_pop: number;
};

function fmtEur(v: number): string {
    return v.toLocaleString("nl-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function avgOr(arr: number[], fallback = 0): number {
    if (arr.length === 0) return fallback;
    return arr.reduce((a, b) => a + b, 0) / arr.length;
}

export default async function LoonkloofPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    async function refreshMart() {
        "use server";
        const supabase = await createClient();
        await supabase.rpc("refresh_mart_loonkloof", {
            p_rechtsgrondslag: "manual refresh via dashboard loonkloof page",
        });
        revalidatePath(`/dashboard/${accountSlug}/loonkloof`);
    }

    // Load mart_loonkloof gefilterd op laatste kwartaal + join met functie
    const { data: martData, error } = await supabase
        .from("mart_loonkloof")
        .select("persoon_id, referentiedatum, kwartaal, uurloon_bruto, basis_vte, variabele_vte, geslacht, functieniveau, ancienniteit_jaren")
        .eq("referentiedatum", "2024-06-30");
    const rows = (martData ?? []) as MartRow[];

    // Load Kitagawa-decompositie via GDPR-safe RPC (T-033)
    const { data: decompData } = await supabase.rpc("mart_loonkloof_decomp_read", {
        p_rechtsgrondslag: "loonkloof analysepagina — decompositie weergave",
        p_kwartaal: "2024-Q2",
    });
    const decomp = ((decompData ?? []) as DecompRow[])[0] ?? null;

    // Aggregate per geslacht
    const m = rows.filter((r) => r.geslacht === "m");
    const v = rows.filter((r) => r.geslacht === "v");
    const avgM = avgOr(m.map((r) => Number(r.uurloon_bruto)));
    const avgV = avgOr(v.map((r) => Number(r.uurloon_bruto)));
    const rawGap = avgM > 0 ? ((avgM - avgV) / avgM) * 100 : 0;
    const avgBasisM = avgOr(m.map((r) => Number(r.basis_vte)));
    const avgBasisV = avgOr(v.map((r) => Number(r.basis_vte)));

    // Load functies apart om te kunnen groeperen
    const { data: functiesData } = await supabase.from("dim_functie").select("functie_id, functienaam, functieniveau");
    const functies = (functiesData ?? []) as { functie_id: string; functienaam: string; functieniveau: number }[];

    // Group per functieniveau band voor loonkloof context
    const nivelen = new Map<number, MartRow[]>();
    for (const r of rows) {
        const arr = nivelen.get(r.functieniveau) ?? [];
        arr.push(r);
        nivelen.set(r.functieniveau, arr);
    }
    const nivelenGap = Array.from(nivelen.entries())
        .map(([niveau, arr]) => {
            const nm = arr.filter((r) => r.geslacht === "m");
            const nv = arr.filter((r) => r.geslacht === "v");
            const naam = functies.find((f) => f.functieniveau === niveau)?.functienaam ?? `Niveau ${niveau}`;
            return {
                niveau,
                naam,
                total: arr.length,
                mCount: nm.length,
                vCount: nv.length,
                avgM: avgOr(nm.map((r) => Number(r.uurloon_bruto))),
                avgV: avgOr(nv.map((r) => Number(r.uurloon_bruto))),
            };
        })
        .sort((a, b) => a.niveau - b.niveau);

    return (
        <div className="mx-auto max-w-6xl py-8 space-y-6">
            <div className="flex items-start justify-between">
                <div>
                    <h1 className="text-3xl font-bold flex items-center gap-2">
                        <Scale className="h-7 w-7" />
                        Loonkloof analyse
                    </h1>
                    <p className="text-muted-foreground text-sm mt-1">
                        Bruto uurloon per geslacht × functieniveau — bron: <code>mart_loonkloof</code> Q2 2024
                    </p>
                </div>
                <form action={refreshMart}>
                    <Button type="submit" variant="outline" size="sm">
                        <RefreshCw className="h-4 w-4 mr-2" />
                        Refresh mart
                    </Button>
                </form>
            </div>

            {error && (
                <Card>
                    <CardContent className="pt-6"><p className="text-red-500 text-sm">Error: {error.message}</p></CardContent>
                </Card>
            )}

            {/* Aggregate KPI */}
            <div className="grid gap-4 md:grid-cols-3">
                <Card>
                    <CardContent className="pt-6">
                        <div className="text-xs uppercase text-muted-foreground">Gem. uurloon mannen</div>
                        <div className="text-2xl font-semibold mt-2 tabular-nums">€ {fmtEur(avgM)}</div>
                        <div className="text-xs text-muted-foreground mt-1">n = {m.length} contracten</div>
                    </CardContent>
                </Card>
                <Card>
                    <CardContent className="pt-6">
                        <div className="text-xs uppercase text-muted-foreground">Gem. uurloon vrouwen</div>
                        <div className="text-2xl font-semibold mt-2 tabular-nums">€ {fmtEur(avgV)}</div>
                        <div className="text-xs text-muted-foreground mt-1">n = {v.length} contracten</div>
                    </CardContent>
                </Card>
                <Card className={Math.abs(rawGap) > 5 ? "bg-orange-50 dark:bg-orange-950/20" : "bg-secondary"}>
                    <CardContent className="pt-6">
                        <div className="text-xs uppercase text-muted-foreground">Ruwe pay gap</div>
                        <div className="text-2xl font-semibold mt-2 tabular-nums flex items-center gap-2">
                            <GapIcon value={rawGap} />
                            {rawGap.toFixed(1)}%
                        </div>
                        <div className="text-xs text-muted-foreground mt-1">
                            {rawGap > 0 ? "Mannen verdienen meer" : rawGap < 0 ? "Vrouwen verdienen meer" : "Gelijk"} (ongecontroleerd)
                        </div>
                    </CardContent>
                </Card>
            </div>

            {/* Kitagawa decomposition — T-033 */}
            {decomp && (decomp.n_m > 0 && decomp.n_v > 0) && (
                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <SplitSquareHorizontal className="h-5 w-5" />
                            Loonkloof decompositie
                            <Badge variant="outline" className="text-xs font-normal">Kitagawa · POC</Badge>
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <DecompositionCard decomp={decomp} />
                    </CardContent>
                </Card>
            )}

            {/* Uurloon basis vs variabele split */}
            <Card>
                <CardHeader>
                    <CardTitle>Basis vs variabele beloning (VTE-basis)</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="grid gap-4 md:grid-cols-2">
                        <BarCompare label="Gemiddelde basis-VTE" mannen={avgBasisM} vrouwen={avgBasisV} />
                        <BarCompare
                            label="Gemiddelde variabele-VTE"
                            mannen={avgOr(m.map((r) => Number(r.variabele_vte)))}
                            vrouwen={avgOr(v.map((r) => Number(r.variabele_vte)))}
                        />
                    </div>
                </CardContent>
            </Card>

            {/* Per functieniveau */}
            <Card>
                <CardHeader>
                    <CardTitle>Loonkloof per team / functieniveau</CardTitle>
                </CardHeader>
                <CardContent>
                    <table className="w-full text-sm">
                        <thead>
                            <tr className="border-b text-left text-xs text-muted-foreground">
                                <th className="pb-2 pr-3">Team</th>
                                <th className="pb-2 pr-3 text-right">Populatie</th>
                                <th className="pb-2 pr-3 text-right">Man n</th>
                                <th className="pb-2 pr-3 text-right">Vrouw n</th>
                                <th className="pb-2 pr-3 text-right">Gem. uurloon M</th>
                                <th className="pb-2 pr-3 text-right">Gem. uurloon V</th>
                                <th className="pb-2 pr-3 text-right">Gap %</th>
                            </tr>
                        </thead>
                        <tbody>
                            {nivelenGap.map((n) => {
                                const gap = n.avgM > 0 ? ((n.avgM - n.avgV) / n.avgM) * 100 : 0;
                                return (
                                    <tr key={n.niveau} className="border-b hover:bg-muted/40">
                                        <td className="py-2 pr-3 font-medium">{n.naam}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">{n.total}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">{n.mCount}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">{n.vCount}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {fmtEur(n.avgM)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {fmtEur(n.avgV)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums font-semibold">
                                            <span className={gap > 3 ? "text-orange-600" : gap < -3 ? "text-green-600" : ""}>
                                                {gap > 0 ? "+" : ""}{gap.toFixed(1)}%
                                            </span>
                                        </td>
                                    </tr>
                                );
                            })}
                        </tbody>
                    </table>
                    <p className="text-xs text-muted-foreground mt-4">
                        Ruwe (ongecorrigeerde) gap per team. Voor de <em>gecorrigeerde</em> splitsing (endowment vs residual) — zie decompositie kaart boven. Volwaardige Oaxaca-Blinder met OLS-coëfficiënten + p-values wordt post-POC toegevoegd via externe stats-service.
                    </p>
                </CardContent>
            </Card>

            <div className="text-xs text-muted-foreground">
                GDPR: dim_persoon.geslacht + opleidingsniveau zijn beschermde kolommen. Deze pagina roept mart_loonkloof aan via geagregeerde views — direct SELECT op dim_persoon protected columns is REVOKED (T-004 + T-034). Access-log via <code>gdpr_access_log</code>.
            </div>
        </div>
    );
}

function DecompositionCard({ decomp }: { decomp: DecompRow }) {
    const rawGap = Number(decomp.raw_gap);
    const endowment = Number(decomp.endowment_gap);
    const residual = Number(decomp.residual_gap);
    const ci = Number(decomp.raw_gap_ci95_halfwidth);
    const rawGapPct = decomp.gem_uurloon_m > 0 ? (rawGap / Number(decomp.gem_uurloon_m)) * 100 : 0;
    const residualPct = decomp.gem_uurloon_m > 0 ? (residual / Number(decomp.gem_uurloon_m)) * 100 : 0;
    const totalAbs = Math.abs(endowment) + Math.abs(residual);
    const endowmentShare = totalAbs > 0 ? Math.abs(endowment) / totalAbs : 0;
    const residualShare = totalAbs > 0 ? Math.abs(residual) / totalAbs : 0;
    const rawSignificant = Math.abs(rawGap) > ci;

    return (
        <div className="space-y-6">
            <div className="grid gap-4 md:grid-cols-3">
                <div className="rounded-lg border p-4 space-y-1">
                    <div className="text-xs uppercase text-muted-foreground">Ruwe kloof</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(rawGap))}</div>
                    <div className="text-xs text-muted-foreground">
                        {rawGap >= 0 ? "mannen +" : "vrouwen +"}{Math.abs(rawGapPct).toFixed(1)}% per uur
                    </div>
                    <div className="text-xs text-muted-foreground mt-2">
                        95% CI: ± € {fmtEur(ci)} · {rawSignificant ? "✓ significant" : "⚠ niet significant"}
                    </div>
                </div>

                <div className="rounded-lg border p-4 bg-blue-50 dark:bg-blue-950/20 space-y-1">
                    <div className="text-xs uppercase text-muted-foreground">Endowment (verklaarbaar)</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(endowment))}</div>
                    <div className="text-xs text-muted-foreground">
                        {(endowmentShare * 100).toFixed(0)}% van de kloof
                    </div>
                    <div className="text-xs text-muted-foreground mt-2 italic">
                        Verschillen in observables (functieniveau, opleiding, ancienniteit)
                    </div>
                </div>

                <div className={`rounded-lg border p-4 space-y-1 ${Math.abs(residual) > ci ? "bg-orange-50 dark:bg-orange-950/20 border-orange-500/40" : "bg-secondary"}`}>
                    <div className="text-xs uppercase text-muted-foreground">Residual (onverklaarbaar)</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(residual))}</div>
                    <div className="text-xs text-muted-foreground">
                        {(residualShare * 100).toFixed(0)}% · {Math.abs(residualPct).toFixed(1)}% per uur
                    </div>
                    <div className="text-xs text-muted-foreground mt-2 italic">
                        Binnen-stratum verschil na controle op observables
                    </div>
                </div>
            </div>

            {/* Stacked bar visualisatie */}
            <div>
                <div className="flex justify-between text-xs text-muted-foreground mb-2">
                    <span>Endowment</span>
                    <span>Residual</span>
                </div>
                <div className="flex h-8 rounded-full overflow-hidden border">
                    <div
                        className="bg-blue-500 flex items-center justify-center text-xs text-white font-medium"
                        style={{ width: `${endowmentShare * 100}%` }}
                    >
                        {endowmentShare > 0.1 && `${(endowmentShare * 100).toFixed(0)}%`}
                    </div>
                    <div
                        className={`flex items-center justify-center text-xs text-white font-medium ${Math.abs(residual) > ci ? "bg-orange-500" : "bg-gray-400"}`}
                        style={{ width: `${residualShare * 100}%` }}
                    >
                        {residualShare > 0.1 && `${(residualShare * 100).toFixed(0)}%`}
                    </div>
                </div>
            </div>

            <div className="text-xs text-muted-foreground space-y-1">
                <p>
                    <strong>Methode</strong>: stratified Kitagawa-decompositie. Strata = functieniveau × opleidingsniveau × ancienniteit-bucket. Populatie in matched strata: {decomp.matched_stratum_pop} contracten.
                </p>
                <p>
                    <strong>Interpretatie</strong>: het <span className="text-blue-600 dark:text-blue-400">blauwe</span> deel verdwijnt als M en V dezelfde functie-/opleidings-/ervaringsverdeling hadden. Het {Math.abs(residual) > ci ? <span className="text-orange-600">oranje</span> : "grijze"} deel blijft over — hoe kleiner, hoe minder onverklaard.
                </p>
                <p>
                    <strong>Beperking</strong>: geen individuele coëfficiënten of p-values per variabele — dit vereist multivariate OLS (post-POC via externe R/Python service). CI via normale benadering (mag afwijken bij kleine n).
                </p>
            </div>
        </div>
    );
}

function GapIcon({ value }: { value: number }) {
    if (Math.abs(value) < 1) return <Minus className="h-5 w-5 text-muted-foreground" />;
    if (value > 0) return <TrendingUp className="h-5 w-5 text-orange-500" />;
    return <TrendingDown className="h-5 w-5 text-green-600" />;
}

function BarCompare({ label, mannen, vrouwen }: { label: string; mannen: number; vrouwen: number }) {
    const max = Math.max(mannen, vrouwen, 1);
    const mPct = (mannen / max) * 100;
    const vPct = (vrouwen / max) * 100;
    return (
        <div>
            <div className="text-sm font-medium mb-3">{label}</div>
            <div className="space-y-2">
                <div>
                    <div className="flex justify-between text-xs mb-1">
                        <span>Mannen</span>
                        <span className="tabular-nums">€ {fmtEur(mannen)}</span>
                    </div>
                    <div className="h-3 bg-muted rounded-full overflow-hidden">
                        <div className="h-full bg-blue-500 rounded-full transition-all" style={{ width: `${mPct}%` }} />
                    </div>
                </div>
                <div>
                    <div className="flex justify-between text-xs mb-1">
                        <span>Vrouwen</span>
                        <span className="tabular-nums">€ {fmtEur(vrouwen)}</span>
                    </div>
                    <div className="h-3 bg-muted rounded-full overflow-hidden">
                        <div className="h-full bg-purple-500 rounded-full transition-all" style={{ width: `${vPct}%` }} />
                    </div>
                </div>
            </div>
        </div>
    );
}
