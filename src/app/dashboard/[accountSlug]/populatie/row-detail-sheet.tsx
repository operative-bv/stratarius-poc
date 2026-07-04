"use client";

import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Badge } from "@/components/ui/badge";
import { Info, ExternalLink } from "lucide-react";

export type PopRow = {
    contract_id: string;
    persoon_id: string;
    pc_id: string;
    status: string;
    werkgeverscategorie: number;
    functienaam: string;
    bruto: number;
    stap2_basis_rsz: number;
    stap3_vermindering: number;
    stap5_bijzondere: number;
    stap6_vakantiegeld: number;
    stap7_extralegaal: number;
    totaal_patronale_kost: number;
    tco: number;
};

export type RSZParam = {
    status: string;
    werkgeverscategorie: number;
    basisbijdrage_pct: number;
    basisfactor_pct: number;
    bron_url: string;
};

export type StructureleParam = {
    werkgeverscategorie: number;
    forfait: number;
    coefficient_a: number;
    coefficient_b: number;
    drempel_s0: number;
    drempel_s1: number;
    bron_url: string;
};

export type ExtralegaalDetail = {
    component_id: string;
    name: string;
    bedrag: number;
    bron_ref: string | null;
};

function fmt(n: number): string {
    return n.toLocaleString("nl-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function pct(n: number): string {
    return (n * 100).toLocaleString("nl-BE", { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

// S0 en S1 komen uit param_structurele_vermindering (per werkgeverscategorie,
// effective-dated). Hardcoded fallbacks alleen wanneer DB-lookup faalt.
const S0_FALLBACK = 10797.67;
const S1_FALLBACK = 6807.18;

export function RowDetailSheet({
    row,
    rszParams,
    structureleParams,
    extralegaalDetails,
    periode,
}: {
    row: PopRow;
    rszParams: RSZParam[];
    structureleParams: StructureleParam[];
    extralegaalDetails: ExtralegaalDetail[];
    periode: string;
}) {
    const rsz = rszParams.find(
        (p) => p.status === row.status && p.werkgeverscategorie === row.werkgeverscategorie,
    );
    const structureel = structureleParams.find((p) => p.werkgeverscategorie === row.werkgeverscategorie);

    // Reconstructie stap 1 (grondslag)
    const factor = row.status === "arbeider" ? Number(rsz?.basisfactor_pct ?? 1.08) : 1.0;
    const grondslag = row.bruto * factor;

    // Reconstructie stap 2 (basis RSZ)
    const basisbijdrage = Number(rsz?.basisbijdrage_pct ?? 0.2507);
    const stap2Recon = grondslag * basisbijdrage;

    // Reconstructie stap 3 (structurele vermindering) — RSZ 1 april 2024 formule.
    // Beide componenten zijn low-side kickers (S onder drempel geeft vermindering).
    // Voorheen: β × max(0, S-S1) hoge-lonen — verwijderd voor cat 1 in 2024.
    const S = row.bruto * 3; // kwartaalloon
    const F = Number(structureel?.forfait ?? 0);
    const a = Number(structureel?.coefficient_a ?? 0.14);
    const b = Number(structureel?.coefficient_b ?? 0);
    const S0 = Number(structureel?.drempel_s0 ?? S0_FALLBACK);
    const S1 = Number(structureel?.drempel_s1 ?? S1_FALLBACK);
    const lageDeel = Math.max(0, S0 - S);
    const zeerLageDeel = Math.max(0, S1 - S);
    const stap3ReconMaand = (F + a * lageDeel + b * zeerLageDeel) / 3;

    // Stap 5 tariefopsplitsing — loonmatiging op 0 (al in stap 2 basisbijdrage 25%)
    const FSO = 0.001;
    const BEV = 0.0016;
    const asbest = 0.0001;
    const loonmatiging = 0.0000;
    const stap5Pct = FSO + BEV + asbest + loonmatiging;

    // Stap 6 tarieven — jaarlijkse rates gedeeld door 12 voor maand-accrual
    const vakEnkelJaar = row.status === "arbeider" ? 0.1538 : 0.0767;
    const vakDubbelJaar = row.status === "arbeider" ? 0 : 0.92;
    const stap6Pct = (vakEnkelJaar + vakDubbelJaar) / 12;

    // Patronale % voor sanity-check badge
    const patronalePct = row.bruto > 0 ? (row.totaal_patronale_kost / row.bruto) * 100 : 0;
    const patronaleGezond = patronalePct >= 25 && patronalePct <= 45;

    return (
        <Sheet>
            <TooltipProvider>
                <Tooltip>
                    <SheetTrigger asChild>
                        <TooltipTrigger asChild>
                            <button
                                type="button"
                                className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-primary hover:underline"
                                aria-label="Toon berekening"
                            >
                                <Info className="h-3.5 w-3.5" />
                            </button>
                        </TooltipTrigger>
                    </SheetTrigger>
                    <TooltipContent side="left">
                        Toon volledige rekencascade voor dit contract
                    </TooltipContent>
                </Tooltip>
            </TooltipProvider>
            <SheetContent
                side="right"
                className="w-full sm:max-w-xl md:max-w-2xl p-0 flex flex-col data-[state=open]:duration-200 data-[state=closed]:duration-150 data-[state=open]:ease-out"
            >
                <SheetHeader className="p-6 pb-4 border-b bg-background sticky top-0 z-10">
                    <SheetTitle className="flex items-center gap-2 flex-wrap">
                        Rekencascade — {row.functienaam}
                        <Badge variant={row.status === "arbeider" ? "outline" : "secondary"}>{row.status}</Badge>
                        <Badge variant="outline">PC {row.pc_id}</Badge>
                        <Badge variant="outline">cat {row.werkgeverscategorie}</Badge>
                    </SheetTitle>
                    <p className="text-xs text-muted-foreground font-mono">
                        contract {row.contract_id.slice(0, 8)} · periode {periode}
                    </p>
                </SheetHeader>

                <div className="flex-1 overflow-y-auto overscroll-y-none space-y-4 text-sm p-6 pt-4">
                    {/* INPUT */}
                    <Section title="Input">
                        <KV label="Bruto basisloon" value={`€ ${fmt(row.bruto)}`} />
                        <KV label="Status" value={row.status} />
                        <KV label="Werkgeverscategorie" value={String(row.werkgeverscategorie)} />
                        <KV label="Paritair comité" value={row.pc_id} />
                    </Section>

                    {/* STAP 1 */}
                    <Step
                        num="1"
                        title="Grondslag"
                        formula={`bruto × factor_${row.status}`}
                        substitution={`${fmt(row.bruto)} × ${factor.toFixed(4)}`}
                        result={grondslag}
                        bron={rsz?.bron_url}
                        note={row.status === "arbeider"
                            ? "Arbeider: 108% grondslag (KB arbeidersgrondslag)"
                            : "Bediende: 100% grondslag"}
                    />

                    {/* STAP 2 */}
                    <Step
                        num="2"
                        title="Basis patronale RSZ"
                        formula="grondslag × basisbijdrage_pct"
                        substitution={`${fmt(grondslag)} × ${pct(basisbijdrage)}%`}
                        result={stap2Recon}
                        actual={row.stap2_basis_rsz}
                        bron={rsz?.bron_url}
                        note="Basis werkgeversbijdrage sociale zekerheid"
                    />

                    {/* STAP 3 */}
                    <Step
                        num="3"
                        title="Structurele vermindering (kwartaal → maand)"
                        formula="R_kwartaal = F + α · max(0, S0-S) + γ · max(0, S1-S)"
                        substitution={
                            `S=${fmt(S)} (bruto×3)  ·  S0=${fmt(S0)} (lage lonen)  ·  S1=${fmt(S1)} (zeer lage lonen)\n` +
                            `= ${fmt(F)} + ${a.toFixed(4)}·max(0, ${fmt(S0 - S)}) + ${b.toFixed(4)}·max(0, ${fmt(S1 - S)})\n` +
                            `= ${fmt(F)} + ${fmt(a * lageDeel)} + ${fmt(b * zeerLageDeel)}\n` +
                            `→ /3 voor maand: € ${fmt(stap3ReconMaand)}`
                        }
                        result={stap3ReconMaand}
                        actual={row.stap3_vermindering}
                        bron={structureel?.bron_url}
                        note="Belgische lage-lonen KB-vermindering. Wordt AFGETROKKEN van basis-RSZ."
                        negative
                    />

                    {/* STAP 5 */}
                    <Step
                        num="5"
                        title="Bijzondere bijdragen"
                        formula="grondslag × (FSO + BEV + asbest + loonmatiging)"
                        substitution={
                            `${fmt(grondslag)} × (${pct(FSO)}% + ${pct(BEV)}% + ${pct(asbest)}% + ${pct(loonmatiging)}%)\n` +
                            `= ${fmt(grondslag)} × ${pct(stap5Pct)}%`
                        }
                        result={grondslag * stap5Pct}
                        actual={row.stap5_bijzondere}
                        bron="https://www.socialsecurity.be/employer/instructions/"
                        note="FSO (sluitingsfonds), BEV (bijzondere bijdrage vergrijzing), asbest, loonmatiging — 2024 tarieven"
                    />

                    {/* STAP 6 */}
                    <Step
                        num="6"
                        title="Vakantiegeld maand-provisie (jaarrate / 12)"
                        formula={row.status === "arbeider"
                            ? "bruto × 15,38% / 12 (arbeider, vakantiekas jaartarief)"
                            : "bruto × (enkel_jaar + dubbel_jaar) / 12"}
                        substitution={row.status === "arbeider"
                            ? `${fmt(row.bruto)} × ${pct(vakEnkelJaar)}% / 12 = ${fmt(row.bruto)} × ${pct(stap6Pct)}%`
                            : `${fmt(row.bruto)} × (${pct(vakEnkelJaar)}% + ${pct(vakDubbelJaar)}%) / 12 = ${fmt(row.bruto)} × ${pct(stap6Pct)}%`}
                        result={row.bruto * stap6Pct}
                        actual={row.stap6_vakantiegeld}
                        bron="https://www.rjv.be/"
                        note={row.status === "arbeider"
                            ? "Arbeider: RJV vakantiekas dekt enkel+dubbel"
                            : "Bediende: enkel doorbetaald + dubbel provisie (POC skipt eindejaarspremie)"}
                    />

                    {/* STAP 7 */}
                    <Section title="Stap 7 — Extralegaal">
                        {extralegaalDetails.length === 0 ? (
                            <p className="text-xs text-muted-foreground">
                                Geen extralegaal componenten voor dit contract in deze periode.
                            </p>
                        ) : (
                            <div className="space-y-1">
                                {extralegaalDetails.map((c) => (
                                    <div key={c.component_id} className="flex items-center justify-between text-xs">
                                        <span>
                                            <span className="font-mono text-muted-foreground">{c.component_id}</span>
                                            {" · "}
                                            {c.name}
                                            {c.bron_ref && (
                                                <span className="ml-2 text-muted-foreground">({c.bron_ref})</span>
                                            )}
                                        </span>
                                        <span className="tabular-nums">€ {fmt(Number(c.bedrag))}</span>
                                    </div>
                                ))}
                                <div className="flex justify-between border-t pt-1 mt-2 text-xs font-semibold">
                                    <span>Som extralegaal</span>
                                    <span className="tabular-nums">€ {fmt(row.stap7_extralegaal)}</span>
                                </div>
                            </div>
                        )}
                    </Section>

                    {/* TOTAAL */}
                    <div className="rounded-lg border-2 border-primary/40 bg-secondary p-4 space-y-2">
                        <div className="text-xs uppercase tracking-wide text-muted-foreground">Totaal</div>
                        <TotalRow label="Basis RSZ (stap 2)" value={row.stap2_basis_rsz} />
                        <TotalRow label="Structurele vermindering" value={-row.stap3_vermindering} />
                        <TotalRow label="Bijzondere bijdragen" value={row.stap5_bijzondere} />
                        <TotalRow label="Vakantiegeld provisie" value={row.stap6_vakantiegeld} />
                        <TotalRow label="Extralegaal" value={row.stap7_extralegaal} />
                        <div className="border-t pt-2 flex items-center justify-between font-semibold">
                            <span>Patronale kost totaal</span>
                            <span className="tabular-nums">€ {fmt(row.totaal_patronale_kost)}</span>
                        </div>
                        <div className="flex items-center justify-between text-lg font-bold">
                            <span>TCO (bruto + patronaal)</span>
                            <span className="tabular-nums">€ {fmt(row.tco)}</span>
                        </div>
                        <div className="pt-2 flex items-center gap-2 text-xs">
                            <Badge variant={patronaleGezond ? "outline" : "destructive"}>
                                Patronale = {patronalePct.toFixed(1)}% van bruto
                            </Badge>
                            <span className="text-muted-foreground">
                                verwacht 25–45% voor Belgische werkgeverskost {patronaleGezond ? "✓" : "⚠"}
                            </span>
                        </div>
                    </div>

                    <p className="text-xs text-muted-foreground">
                        Cascade 9 stappen actief inclusief stap 4 doelgroepverminderingen, stap 8 wagen solidariteitsbijdrage, stap 9 arbeidsongevallen. Cijfers via banker&apos;s rounding.
                    </p>
                </div>
            </SheetContent>
        </Sheet>
    );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
    return (
        <div className="rounded-lg border p-3 space-y-1.5">
            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{title}</div>
            {children}
        </div>
    );
}

function KV({ label, value }: { label: string; value: string }) {
    return (
        <div className="flex justify-between text-xs">
            <span className="text-muted-foreground">{label}</span>
            <span className="tabular-nums">{value}</span>
        </div>
    );
}

function Step({
    num,
    title,
    formula,
    substitution,
    result,
    actual,
    bron,
    note,
    negative = false,
}: {
    num: string;
    title: string;
    formula: string;
    substitution: string;
    result: number;
    actual?: number;
    bron?: string;
    note?: string;
    negative?: boolean;
}) {
    const drift = actual !== undefined ? Math.abs(actual - result) : 0;
    const matches = actual !== undefined && drift < 0.02;
    return (
        <div className="rounded-lg border p-3 space-y-2">
            <div className="flex items-baseline justify-between">
                <div className="text-sm font-semibold">Stap {num} — {title}</div>
                <div className={`text-sm font-semibold tabular-nums ${negative ? "text-green-600" : ""}`}>
                    {negative ? "− " : ""}€ {fmt(result)}
                </div>
            </div>
            <div className="text-xs">
                <span className="text-muted-foreground">Formule: </span>
                <code className="font-mono bg-muted px-1.5 py-0.5 rounded">{formula}</code>
            </div>
            <pre className="text-xs bg-muted/40 rounded p-2 whitespace-pre-wrap font-mono">{substitution}</pre>
            {actual !== undefined && (
                <div className="flex items-center gap-2 text-xs">
                    <Badge variant={matches ? "outline" : "destructive"}>
                        DB: € {fmt(actual)} {matches ? "✓" : `⚠ Δ${fmt(drift)}`}
                    </Badge>
                    {!matches && (
                        <span className="text-muted-foreground">reconstructie wijkt af — check params/afronding</span>
                    )}
                </div>
            )}
            {note && <p className="text-xs text-muted-foreground italic">{note}</p>}
            {bron && (
                <a
                    href={bron}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-xs text-blue-500 hover:underline"
                >
                    <ExternalLink className="h-3 w-3" />
                    Bron
                </a>
            )}
        </div>
    );
}

function TotalRow({ label, value }: { label: string; value: number }) {
    return (
        <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">{label}</span>
            <span className="tabular-nums">
                {value < 0 ? "−" : ""}€ {fmt(Math.abs(value))}
            </span>
        </div>
    );
}
