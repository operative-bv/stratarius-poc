import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Scale, TrendingUp, TrendingDown, Minus, SplitSquareHorizontal } from "lucide-react";
import OaxacaSection from "@/components/loonkloof/oaxaca-section";
import { PageHeader } from "@/components/dashboard/page-header";

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

// ISS-079: aggregeert decomp rijen over meerdere entiteiten. Voor
// single-entiteit tenants (huidige POC-normaal) retourneert dit gewoon
// de enige rij. Voor multi-entiteit: weighted average op count (n_m + n_v).
function aggregateDecomp(rows: DecompRow[]): DecompRow | null {
    if (rows.length === 0) return null;
    if (rows.length === 1) return rows[0];
    const totalWeight = rows.reduce((s, r) => s + r.n_m + r.n_v, 0);
    if (totalWeight === 0) return rows[0];
    const weighted = (key: keyof DecompRow) =>
        rows.reduce((s, r) => s + Number(r[key]) * (r.n_m + r.n_v), 0) / totalWeight;
    return {
        legale_entiteit_id: rows[0].legale_entiteit_id,
        referentiedatum: rows[0].referentiedatum,
        kwartaal: rows[0].kwartaal,
        n_m: rows.reduce((s, r) => s + r.n_m, 0),
        n_v: rows.reduce((s, r) => s + r.n_v, 0),
        gem_uurloon_m: weighted("gem_uurloon_m"),
        gem_uurloon_v: weighted("gem_uurloon_v"),
        raw_gap: weighted("raw_gap"),
        residual_gap: weighted("residual_gap"),
        endowment_gap: weighted("endowment_gap"),
        raw_gap_ci95_halfwidth: weighted("raw_gap_ci95_halfwidth"),
        matched_stratum_pop: rows.reduce((s, r) => s + r.matched_stratum_pop, 0),
    };
}

export default async function LoonkloofPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    // ISS-078: tenant-lookup error EXPLICIET checken — silent failure zou
    // de cross-tenant leak-fix uit 79b22f4 ondermijnen (entiteitIds=[]
    // fallback ziet er uit als "lege tenant" maar kan een echte error zijn).
    const { data: entiteitenData, error: entiteitErr } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id");
    const entiteitIds = (entiteitenData ?? []).map((e: { legale_entiteit_id: string }) => e.legale_entiteit_id);
    const showsMultiEntiteitWarning = entiteitIds.length > 1;

    let error: { message: string } | null = entiteitErr
        ? { message: `Tenant lookup faalde: ${entiteitErr.message}` }
        : null;
    let rows: MartRow[] = [];
    let decomp: DecompRow | null = null;

    if (!error && entiteitIds.length > 0) {
        // mart_loonkloof is nu een tabel met RLS op owning_account_id — Postgres filtert
        // automatisch tot caller's eigen tenant. Geen expliciete .in() filter meer nodig.
        const { data: martData, error: martErr } = await supabase
            .from("mart_loonkloof")
            .select("persoon_id, referentiedatum, kwartaal, uurloon_bruto, basis_vte, variabele_vte, geslacht, functieniveau, ancienniteit_jaren")
            .eq("referentiedatum", "2026-06-30");
        if (martErr) error = { message: `Mart-query faalde: ${martErr.message}` };
        rows = (martData ?? []) as MartRow[];

        // ISS-079: multi-entiteit — RPC is single-entiteit; loop + aggregate
        // Voor POC met single-entiteit tenants is dit één call.
        const decompResults = await Promise.all(
            entiteitIds.map((id) =>
                supabase.rpc("mart_loonkloof_decomp_read", {
                    p_rechtsgrondslag: "loonkloof analysepagina — decompositie weergave",
                    p_kwartaal: "2026-Q2",
                    p_legale_entiteit_id: id,
                }),
            ),
        );
        const decompErr = decompResults.find((r) => r.error)?.error;
        if (decompErr && !error) error = { message: `Decomp-RPC faalde: ${decompErr.message}` };
        const allDecomps = decompResults.flatMap((r) => (r.data ?? []) as DecompRow[]);
        decomp = aggregateDecomp(allDecomps);
    }

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
        <div className="space-y-6">
            <PageHeader
                icon={Scale}
                title="Loonkloof analyse"
                description={<>Bruto uurloon per geslacht × functieniveau — bron <code className="text-xs">mart_loonkloof</code> Q2 2026</>}
            />

            {showsMultiEntiteitWarning && (
                <Card>
                    <CardContent className="pt-6">
                        <p className="text-xs text-muted-foreground">
                            Multi-entiteit tenant gedetecteerd ({entiteitIds.length} entiteiten). Decompositie is een
                            weighted average over alle entiteiten. Per-entiteit view komt in een volgende iteratie.
                        </p>
                    </CardContent>
                </Card>
            )}

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

            <OaxacaSection />

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
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Team</TableHead>
                                <TableHead className="text-right">Populatie</TableHead>
                                <TableHead className="text-right">Man n</TableHead>
                                <TableHead className="text-right">Vrouw n</TableHead>
                                <TableHead className="text-right">Gem. uurloon M</TableHead>
                                <TableHead className="text-right">Gem. uurloon V</TableHead>
                                <TableHead className="text-right">Gap %</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {nivelenGap.map((n) => {
                                const gap = n.avgM > 0 ? ((n.avgM - n.avgV) / n.avgM) * 100 : 0;
                                return (
                                    <TableRow key={n.niveau}>
                                        <TableCell className="font-medium">{n.naam}</TableCell>
                                        <TableCell className="text-right tabular-nums">{n.total}</TableCell>
                                        <TableCell className="text-right tabular-nums">{n.mCount}</TableCell>
                                        <TableCell className="text-right tabular-nums">{n.vCount}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {fmtEur(n.avgM)}</TableCell>
                                        <TableCell className="text-right tabular-nums">€ {fmtEur(n.avgV)}</TableCell>
                                        <TableCell className="text-right tabular-nums font-semibold">
                                            <span className={gap > 3 ? "text-orange-600" : gap < -3 ? "text-green-600" : ""}>
                                                {gap > 0 ? "+" : ""}{gap.toFixed(1)}%
                                            </span>
                                        </TableCell>
                                    </TableRow>
                                );
                            })}
                        </TableBody>
                    </Table>
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
