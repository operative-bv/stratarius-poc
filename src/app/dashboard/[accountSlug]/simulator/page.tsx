import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { TrendingUp, ChevronDown, Car, AlertTriangle } from "lucide-react";

type CascadeResult = {
    stap2_basis_rsz: number | null;
    stap3_vermindering: number | null;
    stap5_bijzondere: number | null;
    stap6_vakantiegeld: number | null;
    totaal_patronale_kost: number;
    wagen?: WagenResult;
    error?: string;
};

type WagenResult = {
    lease_maand: number; // werkgeverskost
    vaa_maand: number; // fiscaal voordeel werknemer (excluded)
    vaa_pct: number; // CO2-coefficient
    leeftijd_coef: number; // afschrijvingscoefficient
    minimum_toegepast: boolean;
    brandstof: string;
};

const VAA_MIN_JAAR_2024 = 1600;
const VAA_REF_CO2_BENZINE = 82;
const VAA_REF_CO2_DIESEL = 67;
const VAA_ELECTRIC_PCT = 0.04;
const VAA_COEF_STEP = 0.001;
const VAA_COEF_MIN = 0.04;
const VAA_COEF_MAX = 0.18;
const VAA_BASE_PCT = 0.055;

function berekenLeeftijdCoef(aanschaf: Date, referentie: Date): number {
    const monthsDiff = (referentie.getFullYear() - aanschaf.getFullYear()) * 12 + (referentie.getMonth() - aanschaf.getMonth());
    if (monthsDiff < 12) return 1.0;
    if (monthsDiff < 24) return 0.94;
    if (monthsDiff < 36) return 0.88;
    if (monthsDiff < 48) return 0.82;
    if (monthsDiff < 60) return 0.76;
    return 0.70;
}

function berekenCO2Coef(brandstof: string, co2: number): number {
    if (brandstof === "elektrisch") return VAA_ELECTRIC_PCT;
    const referentie = brandstof === "diesel" ? VAA_REF_CO2_DIESEL : VAA_REF_CO2_BENZINE;
    const raw = VAA_BASE_PCT + (co2 - referentie) * VAA_COEF_STEP;
    return Math.min(VAA_COEF_MAX, Math.max(VAA_COEF_MIN, raw));
}

function berekenVAA(cataloguswaarde: number, co2: number, brandstof: string, aanschaf: Date, referentie: Date): WagenResult {
    const leeftijd_coef = berekenLeeftijdCoef(aanschaf, referentie);
    const vaa_pct = berekenCO2Coef(brandstof, co2);
    // VAA jaar = cataloguswaarde × 6/7 × leeftijd × CO2-coef  (KB VAA-formule)
    const vaa_jaar_raw = cataloguswaarde * (6 / 7) * leeftijd_coef * vaa_pct;
    const vaa_jaar = Math.max(VAA_MIN_JAAR_2024, vaa_jaar_raw);
    return {
        lease_maand: 0, // ingevuld door caller
        vaa_maand: vaa_jaar / 12,
        vaa_pct,
        leeftijd_coef,
        minimum_toegepast: vaa_jaar_raw < VAA_MIN_JAAR_2024,
        brandstof,
    };
}

// Banker's rounding mirror van server-side round_final('display').
// Postgres round() = half-away-from-zero; banker's = half-to-even.
// Voor display/report is banker's DMFA-conform per KB 28/11/1969 art. 34.
function roundFinal(value: number | null): string {
    if (value === null) return "—";
    const scaled = value * 100;
    const floor = Math.floor(scaled);
    const remainder = scaled - floor;
    let cents: number;
    if (Math.abs(remainder - 0.5) < 1e-9) {
        cents = floor % 2 === 0 ? floor : floor + 1;
    } else {
        cents = Math.round(scaled);
    }
    return (cents / 100).toFixed(2);
}

async function simulate(formData: FormData): Promise<CascadeResult> {
    "use server";
    const supabase = await createClient();
    const bruto = Number(formData.get("bruto"));
    const status = String(formData.get("status") ?? "bediende");
    const cat = Number(formData.get("cat") ?? 1);
    const periode = String(formData.get("periode") ?? "2024-01-01");

    if (!bruto || bruto <= 0) return { stap2_basis_rsz: null, stap3_vermindering: null, stap5_bijzondere: null, stap6_vakantiegeld: null, totaal_patronale_kost: 0, error: "Bruto moet > 0 zijn" };

    const [stap2, stap3, stap5, stap6] = await Promise.all([
        supabase.rpc("cascade_stap2_basis_patronale_rsz", { p_grondslag: bruto, p_status: status, p_werkgeverscategorie: cat, p_periode: periode }),
        supabase.rpc("cascade_stap3_structurele_vermindering", { p_rsz_grondslag: bruto * 3, p_mu: 1.0, p_werkgeverscategorie: cat, p_periode: periode }),
        supabase.rpc("cascade_stap5_bijzondere_bijdragen", { p_grondslag: bruto, p_periode: periode }),
        supabase.rpc("cascade_stap6_vakantiegeld", { p_bruto: bruto, p_status: status, p_periode: periode }),
    ]);

    const s2 = stap2.data ? Number(stap2.data) : null;
    const s3 = stap3.data ? Number(stap3.data) : null;
    const s5 = stap5.data ? Number(stap5.data) : null;
    const s6 = stap6.data ? Number(stap6.data) : null;
    const cascadeTotaal = (s2 ?? 0) - (s3 ?? 0) + (s5 ?? 0) + (s6 ?? 0);

    // Optionele wagen
    const catalog = Number(formData.get("catalog") ?? 0);
    const co2 = Number(formData.get("co2") ?? 0);
    const brandstof = String(formData.get("brandstof") ?? "");
    const lease = Number(formData.get("lease") ?? 0);
    const aanschafStr = String(formData.get("aanschaf") ?? "");
    let wagen: WagenResult | undefined;
    if (catalog > 0 && brandstof && aanschafStr) {
        const aanschaf = new Date(aanschafStr);
        const referentie = new Date(periode);
        wagen = berekenVAA(catalog, co2, brandstof, aanschaf, referentie);
        wagen.lease_maand = lease;
    }

    const totaal = cascadeTotaal + (wagen?.lease_maand ?? 0);
    return { stap2_basis_rsz: s2, stap3_vermindering: s3, stap5_bijzondere: s5, stap6_vakantiegeld: s6, totaal_patronale_kost: totaal, wagen };
}

const STAP_DETAILS = {
    stap2: {
        title: "Stap 2 — Basis patronale RSZ",
        formule: "grondslag × basisbijdrage_pct × basisfactor_pct",
        bron: "https://www.socialsecurity.be/employer/instructions/",
        toelichting: "Via param_rsz temporele join op (status, werkgeverscategorie, periode). Bediende basisfactor=1.0; arbeider=1.08 (108% arbeidersgrondslag).",
    },
    stap3: {
        title: "Stap 3 — Structurele vermindering",
        formule: "(F + α × max(0, S0-S) + δ × max(0, S-S1)) × μ",
        bron: "https://www.socialsecurity.be/employer/instructions/",
        toelichting: "Belgische KB structurele lage-lonen vermindering. S = kwartaalloon (bruto × 3). S0=7207.20, S1=12435.31 (2024). Wordt AFGETROKKEN van basis-RSZ.",
    },
    stap5: {
        title: "Stap 5 — Bijzondere bijdragen",
        formule: "grondslag × (fso + bev + asbest + loonmatiging tarieven)",
        bron: "https://www.socialsecurity.be/employer/instructions/",
        toelichting: "FSO 0.10% + BEV 0.16% + asbest 0.01% + loonmatiging 7.75% = 8.02% totaal (2024). POC skipt centenindex-bijdrage.",
    },
    stap6: {
        title: "Stap 6 — Vakantiegeld provisie",
        formule: "bruto × (enkel_pct + dubbel_pct)",
        bron: "https://www.rjv.be/",
        toelichting: "Arbeider 15.38% (vakantiekas dekt beide). Bediende 7.67% enkel doorbetaald + 92% dubbel provisie. POC skipt eindejaarspremie.",
    },
} as const;

export default async function SimulatorPage({
    searchParams,
}: {
    searchParams: Promise<{
        bruto?: string; status?: string; cat?: string; periode?: string;
        catalog?: string; co2?: string; brandstof?: string; aanschaf?: string; lease?: string;
    }>;
}) {
    const params = await searchParams;
    const bruto = params.bruto ? Number(params.bruto) : null;

    let result: CascadeResult | null = null;
    if (bruto && bruto > 0) {
        const fd = new FormData();
        fd.set("bruto", String(bruto));
        fd.set("status", params.status ?? "bediende");
        fd.set("cat", params.cat ?? "1");
        fd.set("periode", params.periode ?? "2024-01-01");
        if (params.catalog) fd.set("catalog", params.catalog);
        if (params.co2) fd.set("co2", params.co2);
        if (params.brandstof) fd.set("brandstof", params.brandstof);
        if (params.aanschaf) fd.set("aanschaf", params.aanschaf);
        if (params.lease) fd.set("lease", params.lease);
        result = await simulate(fd);
    }

    const periodeDate = params.periode ? new Date(params.periode) : new Date("2024-01-01");
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const isForecasting = periodeDate > today;

    return (
        <div className="mx-auto max-w-3xl py-8 space-y-6">
            {isForecasting && (
                <Alert>
                    <TrendingUp className="h-4 w-4" />
                    <AlertTitle className="flex items-center gap-2">
                        Forecasting mode
                        <Badge variant="secondary">{periodeDate.toISOString().slice(0, 10)}</Badge>
                    </AlertTitle>
                    <AlertDescription>
                        Parameter-datum ligt in de toekomst. Cascade gebruikt aangekondigde tarieven (rijen met geldig_van ≤ {periodeDate.toISOString().slice(0, 10)}). Principe I: effective-dating ondersteunt dit natively.
                    </AlertDescription>
                </Alert>
            )}
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        Werkgeverskost simulator
                        {isForecasting && <Badge>Forecast</Badge>}
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <form className="grid gap-4 md:grid-cols-2" method="get">
                        <div className="space-y-2">
                            <Label htmlFor="bruto">Bruto basisloon (EUR)</Label>
                            <Input id="bruto" name="bruto" type="number" step="0.01" defaultValue={params.bruto ?? "4000"} required />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="status">Status</Label>
                            <Select name="status" defaultValue={params.status ?? "bediende"}>
                                <SelectTrigger id="status"><SelectValue /></SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="bediende">Bediende</SelectItem>
                                    <SelectItem value="arbeider">Arbeider</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="cat">Werkgeverscategorie</Label>
                            <Select name="cat" defaultValue={params.cat ?? "1"}>
                                <SelectTrigger id="cat"><SelectValue /></SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="1">Cat 1 (algemeen)</SelectItem>
                                    <SelectItem value="2">Cat 2 (social profit)</SelectItem>
                                    <SelectItem value="3">Cat 3 (beschutte werkplaats)</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="periode">Periode (kwartaal-begin)</Label>
                            <Input id="periode" name="periode" type="date" defaultValue={params.periode ?? "2024-01-01"} />
                        </div>
                        <details className="md:col-span-2 rounded-lg border p-3 [&_svg.chev]:open:rotate-180">
                            <summary className="flex items-center gap-2 cursor-pointer list-none text-sm font-medium">
                                <ChevronDown className="h-4 w-4 transition-transform chev" />
                                <Car className="h-4 w-4" />
                                Bedrijfswagen (optioneel)
                                <Badge variant="outline" className="ml-auto text-xs">stap 8 — VAA-valkuil demo</Badge>
                            </summary>
                            <div className="grid md:grid-cols-2 gap-4 mt-4 pt-4 border-t">
                                <div className="space-y-2">
                                    <Label htmlFor="catalog">Cataloguswaarde (EUR)</Label>
                                    <Input id="catalog" name="catalog" type="number" step="0.01" defaultValue={params.catalog ?? "38000"} placeholder="38000" />
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="co2">CO2 uitstoot (g/km)</Label>
                                    <Input id="co2" name="co2" type="number" defaultValue={params.co2 ?? "130"} placeholder="130" />
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="brandstof">Brandstoftype</Label>
                                    <Select name="brandstof" defaultValue={params.brandstof ?? "diesel"}>
                                        <SelectTrigger id="brandstof"><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                            <SelectItem value="benzine">Benzine</SelectItem>
                                            <SelectItem value="diesel">Diesel</SelectItem>
                                            <SelectItem value="hybride">Hybride</SelectItem>
                                            <SelectItem value="elektrisch">Elektrisch (4% VAA)</SelectItem>
                                            <SelectItem value="cng">CNG</SelectItem>
                                            <SelectItem value="lpg">LPG</SelectItem>
                                        </SelectContent>
                                    </Select>
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="aanschaf">Aanschaffingsdatum</Label>
                                    <Input id="aanschaf" name="aanschaf" type="date" defaultValue={params.aanschaf ?? "2023-06-01"} />
                                </div>
                                <div className="space-y-2 md:col-span-2">
                                    <Label htmlFor="lease">Leasekost per maand (patronaal)</Label>
                                    <Input id="lease" name="lease" type="number" step="0.01" defaultValue={params.lease ?? "650"} placeholder="650" />
                                    <p className="text-xs text-muted-foreground">
                                        Volledige lease-fee excl. BTW — telt volledig als werkgeverskost.
                                    </p>
                                </div>
                            </div>
                        </details>

                        <div className="md:col-span-2">
                            <Button type="submit" className="w-full">Simuleer</Button>
                        </div>
                    </form>
                </CardContent>
            </Card>

            {result && (
                <Card>
                    <CardHeader>
                        <CardTitle>Werkgeverskost breakdown</CardTitle>
                    </CardHeader>
                    <CardContent>
                        {result.error ? (
                            <p className="text-red-500">{result.error}</p>
                        ) : (
                            <div className="space-y-3">
                                <div className="bg-secondary rounded-lg p-4 flex justify-between items-baseline">
                                    <span className="text-sm text-muted-foreground">Totaal patronale kost</span>
                                    <span className="text-2xl font-semibold tabular-nums">€ {roundFinal(result.totaal_patronale_kost)}</span>
                                </div>

                                <Accordion type="multiple" className="w-full">
                                    <DrillDown id="stap2" label={STAP_DETAILS.stap2.title} value={result.stap2_basis_rsz} details={STAP_DETAILS.stap2} />
                                    <DrillDown id="stap3" label={STAP_DETAILS.stap3.title} value={result.stap3_vermindering} negative details={STAP_DETAILS.stap3} />
                                    <DrillDown id="stap5" label={STAP_DETAILS.stap5.title} value={result.stap5_bijzondere} details={STAP_DETAILS.stap5} />
                                    <DrillDown id="stap6" label={STAP_DETAILS.stap6.title} value={result.stap6_vakantiegeld} details={STAP_DETAILS.stap6} />
                                </Accordion>

                                {result.wagen && (
                                    <div className="rounded-lg border-2 border-orange-500/30 bg-orange-500/5 p-4 space-y-3">
                                        <div className="flex items-center gap-2 text-sm font-semibold">
                                            <Car className="h-4 w-4" />
                                            Bedrijfswagen — stap 8
                                        </div>
                                        <div className="flex justify-between text-sm">
                                            <div>
                                                <div className="font-medium">Lease-fee (patronaal)</div>
                                                <div className="text-xs text-muted-foreground">Werkgeverskost, opgenomen in totaal</div>
                                            </div>
                                            <div className="text-right tabular-nums font-semibold">
                                                € {roundFinal(result.wagen.lease_maand)}
                                                <div className="text-xs text-muted-foreground">/ maand</div>
                                            </div>
                                        </div>
                                        <div className="border-t pt-3 flex justify-between text-sm">
                                            <div>
                                                <div className="font-medium flex items-center gap-2">
                                                    VAA — fiscaal voordeel werknemer
                                                    <Badge variant="outline" className="text-xs">buiten werkgeverskost</Badge>
                                                </div>
                                                <div className="text-xs text-muted-foreground">
                                                    Cataloguswaarde × 6/7 × {(result.wagen.leeftijd_coef * 100).toFixed(0)}% (leeftijd) × {(result.wagen.vaa_pct * 100).toFixed(2)}% (CO2/brandstof)
                                                </div>
                                                {result.wagen.minimum_toegepast && (
                                                    <div className="text-xs text-orange-600 mt-1">
                                                        ⚠ Minimum VAA € {roundFinal(VAA_MIN_JAAR_2024 / 12)}/maand toegepast (KB 2024)
                                                    </div>
                                                )}
                                            </div>
                                            <div className="text-right tabular-nums font-semibold text-muted-foreground">
                                                € {roundFinal(result.wagen.vaa_maand)}
                                                <div className="text-xs text-muted-foreground">/ maand</div>
                                            </div>
                                        </div>
                                        <Alert>
                                            <AlertTriangle className="h-4 w-4" />
                                            <AlertTitle className="text-xs">VAA-valkuil — Principe II</AlertTitle>
                                            <AlertDescription className="text-xs">
                                                VAA is een <strong>fiscaal voordeel voor de werknemer</strong> (belast in personenbelasting) — <strong>geen werkgeverskost</strong>. Alleen de lease-fee telt patronaal mee. Deze scheiding is de meest voorkomende classificatie-fout bij interne payroll-berekeningen.
                                            </AlertDescription>
                                        </Alert>
                                    </div>
                                )}

                                <p className="text-xs text-muted-foreground mt-4">
                                    POC-scope: exclusief stap 4 (doelgroepverminderingen), stap 7 (extralegaal componenten, wel via scenario), stap 9 (arbeidsongevallen). Stap 8 wagen: lease patronaal + VAA gescheiden zoals boven. Bedragen via <code>round_final(display)</code> banker&apos;s rounding.
                                </p>
                            </div>
                        )}
                    </CardContent>
                </Card>
            )}
        </div>
    );
}

function DrillDown({
    id,
    label,
    value,
    negative = false,
    details,
}: {
    id: string;
    label: string;
    value: number | null;
    negative?: boolean;
    details: { formule: string; bron: string; toelichting: string };
}) {
    return (
        <AccordionItem value={id} className="border rounded-lg px-3 mb-2 last:mb-0">
            <AccordionTrigger className="hover:no-underline">
                <div className="flex-1 flex justify-between items-center pr-2">
                    <span className="text-sm font-medium">{label}</span>
                    <span className={`text-sm tabular-nums ${negative ? "text-green-600" : ""}`}>
                        {value === null ? "—" : `${negative ? "−" : ""}€ ${roundFinal(value)}`}
                    </span>
                </div>
            </AccordionTrigger>
            <AccordionContent>
                <div className="space-y-2 text-xs pt-2">
                    <div>
                        <span className="text-muted-foreground">Formule: </span>
                        <code className="font-mono">{details.formule}</code>
                    </div>
                    <div>
                        <span className="text-muted-foreground">Uitleg: </span>
                        <span>{details.toelichting}</span>
                    </div>
                    <div>
                        <span className="text-muted-foreground">Bron: </span>
                        <a href={details.bron} target="_blank" rel="noopener noreferrer" className="text-blue-500 underline">{details.bron}</a>
                    </div>
                </div>
            </AccordionContent>
        </AccordionItem>
    );
}
