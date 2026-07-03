import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Users } from "lucide-react";

type PopRow = {
    contract_id: string;
    persoon_id: string;
    pc_id: string;
    status: string;
    werkgeverscategorie: number;
    bruto: number;
    stap2_basis_rsz: number;
    stap3_vermindering: number;
    stap5_bijzondere: number;
    stap6_vakantiegeld: number;
    stap7_extralegaal: number;
    totaal_patronale_kost: number;
    tco: number;
};

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

export default async function PopulatiePage({
    searchParams,
}: {
    searchParams: Promise<{ periode?: string }>;
}) {
    const params = await searchParams;
    const periode = params.periode ?? "2024-06-01";

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("cascade_populatie_snapshot", { p_periode: periode });
    const rows = (data ?? []) as PopRow[];

    const totalBruto = rows.reduce((s, r) => s + Number(r.bruto), 0);
    const totalRSZ = rows.reduce((s, r) => s + Number(r.stap2_basis_rsz), 0);
    const totalVerm = rows.reduce((s, r) => s + Number(r.stap3_vermindering), 0);
    const totalBijz = rows.reduce((s, r) => s + Number(r.stap5_bijzondere), 0);
    const totalVak = rows.reduce((s, r) => s + Number(r.stap6_vakantiegeld), 0);
    const totalExtra = rows.reduce((s, r) => s + Number(r.stap7_extralegaal), 0);
    const totalPatronale = rows.reduce((s, r) => s + Number(r.totaal_patronale_kost), 0);
    const totalTco = rows.reduce((s, r) => s + Number(r.tco), 0);

    return (
        <div className="mx-auto max-w-7xl py-8 space-y-6">
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Users className="h-5 w-5" />
                        Populatie snapshot
                        <Badge variant="secondary">{rows.length} contracten</Badge>
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <form className="flex items-end gap-4" method="get">
                        <div className="space-y-2 flex-1 max-w-xs">
                            <Label htmlFor="periode">Periode</Label>
                            <Input id="periode" name="periode" type="date" defaultValue={periode} />
                        </div>
                        <Button type="submit">Herbereken</Button>
                    </form>
                </CardContent>
            </Card>

            {error && (
                <Card>
                    <CardContent className="pt-6">
                        <p className="text-red-500">Error: {error.message}</p>
                    </CardContent>
                </Card>
            )}

            {rows.length > 0 && (
                <Card>
                    <CardContent className="pt-6 overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead>
                                <tr className="border-b text-left text-xs text-muted-foreground">
                                    <th className="pb-2 pr-3">Contract</th>
                                    <th className="pb-2 pr-3">Status</th>
                                    <th className="pb-2 pr-3">PC</th>
                                    <th className="pb-2 pr-3 text-right">Bruto</th>
                                    <th className="pb-2 pr-3 text-right">Basis RSZ</th>
                                    <th className="pb-2 pr-3 text-right text-green-600">Vermindering</th>
                                    <th className="pb-2 pr-3 text-right">Bijzondere</th>
                                    <th className="pb-2 pr-3 text-right">Vakantiegeld</th>
                                    <th className="pb-2 pr-3 text-right">Extralegaal</th>
                                    <th className="pb-2 pr-3 text-right font-semibold">Patronaal</th>
                                    <th className="pb-2 text-right font-semibold">TCO</th>
                                </tr>
                            </thead>
                            <tbody>
                                {rows.map((r) => (
                                    <tr key={r.contract_id} className="border-b hover:bg-muted/40">
                                        <td className="py-2 pr-3 font-mono text-xs">{r.contract_id.slice(0, 8)}</td>
                                        <td className="py-2 pr-3">
                                            <Badge variant={r.status === "arbeider" ? "outline" : "secondary"}>{r.status}</Badge>
                                        </td>
                                        <td className="py-2 pr-3">{r.pc_id}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {roundFinal(r.bruto)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {roundFinal(r.stap2_basis_rsz)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums text-green-600">−€ {roundFinal(r.stap3_vermindering)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {roundFinal(r.stap5_bijzondere)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {roundFinal(r.stap6_vakantiegeld)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums">€ {roundFinal(r.stap7_extralegaal)}</td>
                                        <td className="py-2 pr-3 text-right tabular-nums font-semibold">€ {roundFinal(r.totaal_patronale_kost)}</td>
                                        <td className="py-2 text-right tabular-nums font-semibold">€ {roundFinal(r.tco)}</td>
                                    </tr>
                                ))}
                            </tbody>
                            <tfoot>
                                <tr className="border-t-2 font-semibold bg-muted/40">
                                    <td className="py-3 pr-3" colSpan={3}>Totaal populatie ({rows.length})</td>
                                    <td className="py-3 pr-3 text-right tabular-nums">€ {roundFinal(totalBruto)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums">€ {roundFinal(totalRSZ)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums text-green-600">−€ {roundFinal(totalVerm)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums">€ {roundFinal(totalBijz)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums">€ {roundFinal(totalVak)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums">€ {roundFinal(totalExtra)}</td>
                                    <td className="py-3 pr-3 text-right tabular-nums text-primary">€ {roundFinal(totalPatronale)}</td>
                                    <td className="py-3 text-right tabular-nums text-primary">€ {roundFinal(totalTco)}</td>
                                </tr>
                            </tfoot>
                        </table>
                        <p className="text-xs text-muted-foreground mt-4">
                            POC subset: exclusief stap 4 (doelgroepverminderingen), stap 8-9 (wagen, arbeidsongevallen). Bedragen via <code>round_final(display)</code> banker&apos;s rounding. RLS filtert automatisch op tenant.
                        </p>
                    </CardContent>
                </Card>
            )}

            {rows.length === 0 && !error && (
                <Card>
                    <CardContent className="pt-6">
                        <p className="text-muted-foreground">Geen contracten gevonden voor periode {periode}. Check dat je legale entiteiten + contracten hebt geseed voor deze tenant.</p>
                    </CardContent>
                </Card>
            )}
        </div>
    );
}
