import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { TrendingUp, ChevronDown } from "lucide-react";

type CascadeResult = {
    stap2_basis_rsz: number | null;
    stap3_vermindering: number | null;
    stap5_bijzondere: number | null;
    stap6_vakantiegeld: number | null;
    totaal_patronale_kost: number;
    error?: string;
};

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
    const totaal = (s2 ?? 0) - (s3 ?? 0) + (s5 ?? 0) + (s6 ?? 0);

    return { stap2_basis_rsz: s2, stap3_vermindering: s3, stap5_bijzondere: s5, stap6_vakantiegeld: s6, totaal_patronale_kost: totaal };
}

const STAP_DETAILS = {
    stap2: {
        title: "Stap 2 — Basis patronale RSZ",
        formule: "grondslag × basisbijdrage_pct × basisfactor_arbeider_pct",
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
    searchParams: Promise<{ bruto?: string; status?: string; cat?: string; periode?: string }>;
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

                                <DrillDown label={STAP_DETAILS.stap2.title} value={result.stap2_basis_rsz} details={STAP_DETAILS.stap2} />
                                <DrillDown label={STAP_DETAILS.stap3.title} value={result.stap3_vermindering} negative details={STAP_DETAILS.stap3} />
                                <DrillDown label={STAP_DETAILS.stap5.title} value={result.stap5_bijzondere} details={STAP_DETAILS.stap5} />
                                <DrillDown label={STAP_DETAILS.stap6.title} value={result.stap6_vakantiegeld} details={STAP_DETAILS.stap6} />

                                <p className="text-xs text-muted-foreground mt-4">
                                    POC-scope: exclusief stap 1 (grondslag = bruto), stap 4 (doelgroepverminderingen), stap 7 (extralegaal), stap 8-9 (wagen, arbeidsongevallen). Bedragen gerenderd via <code>round_final(display)</code> banker&apos;s rounding — Principe III geen inline <code>.toFixed()</code>.
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
    label,
    value,
    negative = false,
    details,
}: {
    label: string;
    value: number | null;
    negative?: boolean;
    details: { formule: string; bron: string; toelichting: string };
}) {
    return (
        <details className="rounded-lg border p-3 [&_svg]:open:rotate-180">
            <summary className="flex justify-between items-center cursor-pointer list-none">
                <span className="flex items-center gap-2 text-sm font-medium">
                    <ChevronDown className="h-4 w-4 transition-transform" />
                    {label}
                </span>
                <span className={`text-sm tabular-nums ${negative ? "text-green-600" : ""}`}>
                    {value === null ? "—" : `${negative ? "−" : ""}€ ${roundFinal(value)}`}
                </span>
            </summary>
            <div className="mt-3 pt-3 border-t space-y-2 text-xs">
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
        </details>
    );
}
