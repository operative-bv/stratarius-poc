import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Upload, FileSpreadsheet, Link2, Info, CheckCircle2, XCircle } from "lucide-react";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

// CSV row shape (verwacht):
// naam,geslacht,geboortedatum,opleidingsniveau,team,status,pc,bruto
type ImportResult = { created: number; skipped: number; errors: string[] };

async function importCsv(formData: FormData): Promise<void> {
    "use server";
    const file = formData.get("csv") as File | null;
    const accountSlug = String(formData.get("accountSlug") ?? "");
    if (!file || file.size === 0) {
        redirect(`/dashboard/${accountSlug}/import?error=Geen bestand geselecteerd`);
    }

    const text = await (file as File).text();
    const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
    if (lines.length < 2) {
        redirect(`/dashboard/${accountSlug}/import?error=CSV moet header + minstens 1 rij bevatten`);
    }

    const supabase = await createClient();

    // Fetch tenant setup — legale entiteit + functies + baseline scenario
    const [{ data: entData }, { data: funcData }, { data: scenData }] = await Promise.all([
        supabase.from("dim_legale_entiteit").select("legale_entiteit_id, owning_account_id").limit(1),
        supabase.from("dim_functie").select("functie_id, functienaam, owning_account_id"),
        supabase.from("dim_scenario").select("scenario_id").eq("kind", "baseline").limit(1),
    ]);
    const entiteit = entData?.[0];
    const functies = (funcData ?? []) as { functie_id: string; functienaam: string; owning_account_id: string }[];
    const baselineId = scenData?.[0]?.scenario_id;

    if (!entiteit || !baselineId) {
        redirect(`/dashboard/${accountSlug}/import?error=Legale entiteit of baseline scenario ontbreekt`);
    }

    const header = lines[0].split(",").map((h) => h.trim().toLowerCase());
    const col = (row: string[], name: string): string => {
        const idx = header.indexOf(name);
        return idx >= 0 ? row[idx]?.trim() ?? "" : "";
    };

    const result: ImportResult = { created: 0, skipped: 0, errors: [] };

    for (let i = 1; i < lines.length; i++) {
        const row = lines[i].split(",");
        const naam = col(row, "naam");
        const geslacht = col(row, "geslacht").toLowerCase();
        const geboortedatum = col(row, "geboortedatum");
        const opleidingsniveau = col(row, "opleidingsniveau") || "middel_geschoold";
        const team = col(row, "team");
        const status = col(row, "status").toLowerCase() || "bediende";
        const pc = col(row, "pc") || (status === "arbeider" ? "124" : "200");
        const brutoRaw = col(row, "bruto");
        const bruto = brutoRaw ? Number(brutoRaw) : 0;

        if (!naam) {
            result.errors.push(`Rij ${i}: naam ontbreekt`);
            result.skipped++;
            continue;
        }
        if (!["m", "v", "x"].includes(geslacht)) {
            result.errors.push(`Rij ${i} (${naam}): ongeldig geslacht "${geslacht}" (verwacht m/v/x)`);
            result.skipped++;
            continue;
        }
        if (!geboortedatum || !/^\d{4}-\d{2}-\d{2}$/.test(geboortedatum)) {
            result.errors.push(`Rij ${i} (${naam}): geboortedatum moet YYYY-MM-DD zijn`);
            result.skipped++;
            continue;
        }
        if (bruto <= 0) {
            result.errors.push(`Rij ${i} (${naam}): bruto moet > 0 zijn`);
            result.skipped++;
            continue;
        }

        // Find or create functie for team
        let functie: { functie_id: string; functienaam: string; owning_account_id: string } | undefined = functies.find((f) => f.functienaam.toLowerCase() === team.toLowerCase());
        if (!functie && team) {
            const { data: newFunc } = await supabase
                .from("dim_functie")
                .insert({ owning_account_id: entiteit.owning_account_id, functienaam: team, functieniveau: 10 })
                .select("functie_id, functienaam, owning_account_id")
                .single();
            if (newFunc) {
                functie = newFunc;
                functies.push(functie);
            }
        }
        if (!functie) {
            result.errors.push(`Rij ${i} (${naam}): team "${team}" niet gevonden en kon niet worden aangemaakt`);
            result.skipped++;
            continue;
        }

        // Insert dim_persoon → dim_contract → fact_looncomponent
        const { data: persoonInsert, error: persoonErr } = await supabase
            .from("dim_persoon")
            .insert({
                owning_account_id: entiteit.owning_account_id,
                geslacht,
                geboortedatum,
                opleidingsniveau,
            })
            .select("persoon_id")
            .single();

        if (persoonErr || !persoonInsert) {
            result.errors.push(`Rij ${i} (${naam}): persoon insert faalde — ${persoonErr?.message}`);
            result.skipped++;
            continue;
        }

        const { data: contractInsert, error: contractErr } = await supabase
            .from("dim_contract")
            .insert({
                persoon_id: persoonInsert.persoon_id,
                legale_entiteit_id: entiteit.legale_entiteit_id,
                functie_id: functie.functie_id,
                pc_id: pc,
                status,
                fte_breuk: 1.0,
                geldig_van: "2023-01-01",
            })
            .select("contract_id")
            .single();

        if (contractErr || !contractInsert) {
            result.errors.push(`Rij ${i} (${naam}): contract insert faalde — ${contractErr?.message}`);
            result.skipped++;
            continue;
        }

        const { error: factErr } = await supabase.from("fact_looncomponent").insert({
            contract_id: contractInsert.contract_id,
            periode: "2024-06-01",
            component_id: "basisloon",
            scenario_id: baselineId,
            bedrag: bruto,
        });

        if (factErr) {
            result.errors.push(`Rij ${i} (${naam}): fact_looncomponent faalde — ${factErr.message}`);
            result.skipped++;
            continue;
        }

        result.created++;
    }

    revalidatePath(`/dashboard/${accountSlug}`);
    redirect(
        `/dashboard/${accountSlug}/import?created=${result.created}&skipped=${result.skipped}&errors=${encodeURIComponent(result.errors.slice(0, 5).join(" · "))}`,
    );
}

export default async function ImportPage({
    params,
    searchParams,
}: {
    params: Promise<{ accountSlug: string }>;
    searchParams: Promise<{ created?: string; skipped?: string; errors?: string; error?: string }>;
}) {
    const { accountSlug } = await params;
    const sp = await searchParams;

    const supabase = await createClient();
    const { count } = await supabase.from("dim_contract").select("contract_id", { count: "exact", head: true });
    const totalContracts = count ?? 0;

    return (
        <div className="mx-auto max-w-5xl py-8 space-y-6">
            <div>
                <h1 className="text-3xl font-bold flex items-center gap-2">
                    <Upload className="h-7 w-7" />
                    Data import
                </h1>
                <p className="text-muted-foreground text-sm mt-1">
                    Bulk-import contracten + baseline lonen. Momenteel {totalContracts} contracten in populatie.
                </p>
            </div>

            {sp.created && (
                <Alert>
                    <CheckCircle2 className="h-4 w-4" />
                    <AlertTitle>Import compleet</AlertTitle>
                    <AlertDescription>
                        {sp.created} contract{Number(sp.created) !== 1 ? "en" : ""} aangemaakt · {sp.skipped ?? 0} overgeslagen
                        {sp.errors && sp.errors.length > 0 && (
                            <div className="mt-2 text-xs">
                                <strong>Fouten:</strong> {sp.errors}
                            </div>
                        )}
                    </AlertDescription>
                </Alert>
            )}

            {sp.error && (
                <Alert variant="destructive">
                    <XCircle className="h-4 w-4" />
                    <AlertTitle>Fout</AlertTitle>
                    <AlertDescription>{sp.error}</AlertDescription>
                </Alert>
            )}

            <div className="grid gap-6 md:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <FileSpreadsheet className="h-5 w-5" />
                            CSV upload
                            <Badge variant="secondary">Beschikbaar</Badge>
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <form action={importCsv} className="space-y-4">
                            <input type="hidden" name="accountSlug" value={accountSlug} />

                            <div className="space-y-2">
                                <Label htmlFor="csv">Selecteer CSV bestand</Label>
                                <Input id="csv" name="csv" type="file" accept=".csv,text/csv" required />
                            </div>

                            <div className="space-y-2">
                                <div className="flex items-center gap-2 text-sm font-medium">
                                    <Info className="h-4 w-4" />
                                    Verwacht formaat
                                </div>
                                <pre className="text-xs bg-muted rounded-md p-3 overflow-x-auto font-mono leading-relaxed">
{`naam,geslacht,geboortedatum,opleidingsniveau,team,status,pc,bruto
Alice De Vries,v,1985-03-15,hooggeschoold,Sales,bediende,200,4500
Bob Peeters,m,1990-07-22,middel_geschoold,Engineering,bediende,200,5200`}
                                </pre>
                                <ul className="text-xs text-muted-foreground list-disc list-inside space-y-1">
                                    <li><code className="font-mono">geslacht</code>: m / v / x</li>
                                    <li><code className="font-mono">status</code>: bediende / arbeider</li>
                                    <li><code className="font-mono">pc</code>: 200 (bediende) / 124 (bouw arbeider) / etc.</li>
                                    <li><code className="font-mono">team</code>: bestaande functie of nieuwe wordt aangemaakt</li>
                                </ul>
                            </div>

                            <Button type="submit" className="w-full">
                                <Upload className="h-4 w-4 mr-2" />
                                Upload en importeer
                            </Button>
                        </form>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Link2 className="h-5 w-5" />
                            HR-systeem koppelingen
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <p className="text-sm text-muted-foreground mb-4">
                            Directe integraties met payroll- en HR-suites voor continue sync. Roadmap Q3-Q4 2026.
                        </p>

                        <div className="space-y-3">
                            <ConnectorCard name="Workday HCM" desc="Employees API + compensation module" status="Q3 2026" />
                            <ConnectorCard name="BambooHR" desc="Employees + custom fields + org chart" status="Q3 2026" />
                            <ConnectorCard name="SD Worx eBlox" desc="Belgische payroll — directe RSZ-integratie" status="Q4 2026" />
                            <ConnectorCard name="Attentia" desc="Belgische HR + wagen fleet management" status="Q4 2026" />
                        </div>

                        <p className="text-xs text-muted-foreground mt-4">
                            Elk connector-type mapt HR-velden naar Stratarius schema (dim_persoon, dim_contract, fact_looncomponent). Rechtsgrondslag wordt gelogd per sync via <code>gdpr_access_log</code>.
                        </p>
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}

function ConnectorCard({ name, desc, status }: { name: string; desc: string; status: string }) {
    return (
        <div className="flex items-center justify-between border rounded-lg p-3">
            <div>
                <div className="text-sm font-medium">{name}</div>
                <div className="text-xs text-muted-foreground">{desc}</div>
            </div>
            <Badge variant="outline">{status}</Badge>
        </div>
    );
}
