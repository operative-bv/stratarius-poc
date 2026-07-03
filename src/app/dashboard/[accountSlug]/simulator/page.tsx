import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

type CascadeResult = {
    stap2_basis_rsz: number | null;
    stap3_vermindering: number | null;
    stap5_bijzondere: number | null;
    stap6_vakantiegeld: number | null;
    totaal_patronale_kost: number;
    error?: string;
};

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

    return (
        <div className="mx-auto max-w-3xl py-8 space-y-6">
            <Card>
                <CardHeader>
                    <CardTitle>Werkgeverskost simulator</CardTitle>
                </CardHeader>
                <CardContent>
                    <form className="grid gap-4 md:grid-cols-2" action="/dashboard/simulator" method="get">
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
                            <div className="space-y-2">
                                <BreakdownRow label="Stap 2: Basis patronale RSZ" value={result.stap2_basis_rsz} />
                                <BreakdownRow label="Stap 3: Structurele vermindering" value={result.stap3_vermindering} negative />
                                <BreakdownRow label="Stap 5: Bijzondere bijdragen" value={result.stap5_bijzondere} />
                                <BreakdownRow label="Stap 6: Vakantiegeld provisie" value={result.stap6_vakantiegeld} />
                                <div className="border-t pt-2 mt-2 flex justify-between font-semibold">
                                    <span>Totaal patronale kost</span>
                                    <span>€ {result.totaal_patronale_kost.toFixed(2)}</span>
                                </div>
                                <p className="text-xs text-gray-500 mt-4">
                                    POC: exclusief stap 1 (grondslag = bruto), stap 4 (doelgroepverminderingen), stap 7 (extralegaal), stap 8-9 (wagen, arbeidsongevallen).
                                </p>
                            </div>
                        )}
                    </CardContent>
                </Card>
            )}
        </div>
    );
}

function BreakdownRow({ label, value, negative = false }: { label: string; value: number | null; negative?: boolean }) {
    return (
        <div className="flex justify-between">
            <span className="text-sm">{label}</span>
            <span className={`text-sm tabular-nums ${negative ? "text-green-600" : ""}`}>
                {value === null ? "—" : `${negative ? "−" : ""}€ ${value.toFixed(2)}`}
            </span>
        </div>
    );
}
