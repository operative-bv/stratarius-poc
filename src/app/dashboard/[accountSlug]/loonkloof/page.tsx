import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Scale, TrendingUp, TrendingDown, Minus, SplitSquareHorizontal } from "lucide-react";
import OaxacaSection from "@/components/loonkloof/oaxaca-section";
import EntiteitFilter from "@/components/loonkloof/entiteit-filter";
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

type Entiteit = { legale_entiteit_id: string; naam: string };

export default async function LoonkloofPage({
    params,
    searchParams,
}: {
    params: Promise<{ accountSlug: string }>;
    searchParams: Promise<{ entiteit?: string }>;
}) {
    const { accountSlug } = await params;
    const { entiteit: entiteitFilter } = await searchParams;
    const supabase = await createClient();

    // ISS-078: tenant-lookup error EXPLICIET checken — silent failure zou
    // de cross-tenant leak-fix uit 79b22f4 ondermijnen (entiteitIds=[]
    // fallback ziet er uit als "lege tenant" maar kan een echte error zijn).
    const { data: entiteitenData, error: entiteitErr } = await supabase
        .from("dim_legale_entiteit")
        .select("legale_entiteit_id, naam")
        .order("naam", { ascending: true });
    const entiteiten = (entiteitenData ?? []) as Entiteit[];
    const entiteitIds = entiteiten.map((e) => e.legale_entiteit_id);
    const isMultiEntiteit = entiteitIds.length > 1;

    // Valide filter? Anders reset naar "all".
    const activeEntiteitId = entiteitFilter && entiteitIds.includes(entiteitFilter)
        ? entiteitFilter
        : null;

    let error: { message: string } | null = entiteitErr
        ? { message: `Tenant lookup faalde: ${entiteitErr.message}` }
        : null;
    let rows: MartRow[] = [];
    let decomp: DecompRow | null = null;

    if (!error && entiteitIds.length > 0) {
        // mart_loonkloof is nu een tabel met RLS op owning_account_id — Postgres filtert
        // automatisch tot caller's eigen tenant. Optioneel filter op gekozen entiteit.
        let martQuery = supabase
            .from("mart_loonkloof")
            .select("persoon_id, referentiedatum, kwartaal, uurloon_bruto, basis_vte, variabele_vte, geslacht, functieniveau, ancienniteit_jaren, legale_entiteit_id")
            .eq("referentiedatum", "2026-06-30");
        if (activeEntiteitId) martQuery = martQuery.eq("legale_entiteit_id", activeEntiteitId);
        let { data: martData, error: martErr } = await martQuery;
        if (martErr) error = { message: `Mart-query faalde: ${martErr.message}` };

        // Auto-populate cache bij eerste visit (of na invalidation door bulk_import/clear).
        if (!error && (martData ?? []).length === 0) {
            const { error: refreshErr } = await supabase.rpc("refresh_mart_loonkloof", {
                p_rechtsgrondslag: "loonkloof pagina eerste visit — auto-populate cache",
            });
            if (refreshErr) {
                console.error("[loonkloof] mart refresh failed:", refreshErr);
            } else {
                let requeryBuilder = supabase
                    .from("mart_loonkloof")
                    .select("persoon_id, referentiedatum, kwartaal, uurloon_bruto, basis_vte, variabele_vte, geslacht, functieniveau, ancienniteit_jaren, legale_entiteit_id")
                    .eq("referentiedatum", "2026-06-30");
                if (activeEntiteitId) requeryBuilder = requeryBuilder.eq("legale_entiteit_id", activeEntiteitId);
                const requery = await requeryBuilder;
                martData = requery.data;
            }
        }
        rows = (martData ?? []) as MartRow[];

        // Multi-entiteit: als user "alle entiteiten" heeft (geen filter), loop + aggregate.
        // Bij enkele entiteit filter → single-entiteit RPC call.
        const targetEntiteitIds = activeEntiteitId ? [activeEntiteitId] : entiteitIds;
        const decompResults = await Promise.all(
            targetEntiteitIds.map((id) =>
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
                description="Bruto uurloon per geslacht × functieniveau — referentieperiode Q2 2026"
            />

            {isMultiEntiteit && (
                <Card>
                    <CardContent className="pt-6">
                        <EntiteitFilter
                            accountSlug={accountSlug}
                            entiteiten={entiteiten}
                            activeEntiteitId={activeEntiteitId}
                        />
                    </CardContent>
                </Card>
            )}

            {isMultiEntiteit && activeEntiteitId === null && (
                <Card>
                    <CardContent className="pt-4 pb-4">
                        <p className="text-xs text-muted-foreground">
                            Weergave: aggregate over {entiteitIds.length} entiteiten (weighted average op headcount).
                            Kies een specifieke entiteit hierboven voor per-entiteit KPIs.
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

            {decomp && (decomp.n_m > 0 && decomp.n_v > 0) && (
                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <SplitSquareHorizontal className="h-5 w-5" />
                            Loonkloof decompositie
                            <Badge variant="outline" className="text-xs font-normal">Vereenvoudigd model</Badge>
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
                GDPR: geslacht en opleidingsniveau zijn beschermde velden. Deze pagina toont enkel geaggregeerde cijfers
                — geen individuele records. Elke raadpleging wordt gelogd met rechtsgrondslag.
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
        <div className="flex flex-col gap-6">
            <div className="grid gap-4 md:grid-cols-3">
                <Card>
                    <CardContent className="pt-6 flex flex-col gap-1">
                        <div className="text-xs uppercase text-muted-foreground">Ruwe kloof</div>
                        <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(rawGap))}</div>
                        <div className="text-xs text-muted-foreground">
                            {rawGap >= 0 ? "mannen +" : "vrouwen +"}{Math.abs(rawGapPct).toFixed(1)}% per uur
                        </div>
                        <div className="text-xs text-muted-foreground mt-2">
                            95% CI: ± € {fmtEur(ci)} · {rawSignificant ? "✓ significant" : "⚠ niet significant"}
                        </div>
                    </CardContent>
                </Card>

                <Card className="bg-blue-50 dark:bg-blue-950/20">
                    <CardContent className="pt-6 flex flex-col gap-1">
                        <div className="text-xs uppercase text-muted-foreground">Endowment (verklaarbaar)</div>
                        <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(endowment))}</div>
                        <div className="text-xs text-muted-foreground">
                            {(endowmentShare * 100).toFixed(0)}% van de kloof
                        </div>
                        <div className="text-xs text-muted-foreground mt-2 italic">
                            Verschillen in observables (functieniveau, opleiding, ancienniteit)
                        </div>
                    </CardContent>
                </Card>

                <Card className={Math.abs(residual) > ci ? "bg-orange-50 dark:bg-orange-950/20 border-orange-500/40" : "bg-secondary"}>
                    <CardContent className="pt-6 flex flex-col gap-1">
                        <div className="text-xs uppercase text-muted-foreground">Residual (onverklaarbaar)</div>
                        <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(residual))}</div>
                        <div className="text-xs text-muted-foreground">
                            {(residualShare * 100).toFixed(0)}% · {Math.abs(residualPct).toFixed(1)}% per uur
                        </div>
                        <div className="text-xs text-muted-foreground mt-2 italic">
                            Binnen-stratum verschil na controle op observables
                        </div>
                    </CardContent>
                </Card>
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
                    <strong>Methode</strong>: vergelijking op functieniveau, opleidingsniveau en ervaring. Populatie:
                    {" "}{decomp.matched_stratum_pop} medewerkers.
                </p>
                <p>
                    <strong>Interpretatie</strong>: het <span className="text-blue-600 dark:text-blue-400">blauwe</span> deel verdwijnt als mannen en vrouwen dezelfde profielverdeling hadden. Het {Math.abs(residual) > ci ? <span className="text-orange-600">oranje</span> : "grijze"} deel blijft over — hoe kleiner, hoe minder onverklaard.
                </p>
                <p>
                    <strong>Beperking</strong>: dit is een vereenvoudigd model. Individuele wegingen per variabele
                    komen in een volgende iteratie.
                </p>
            </div>
        </div>
    );
}

function GapIcon({ value }: { value: number }) {
    if (Math.abs(value) < 1) return <Minus className="size-5 text-muted-foreground" />;
    if (value > 0) return <TrendingUp className="size-5 text-orange-500" />;
    return <TrendingDown className="size-5 text-green-600" />;
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
