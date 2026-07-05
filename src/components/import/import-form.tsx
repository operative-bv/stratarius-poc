"use client";

import { useEffect } from "react";
import { useFormState, useFormStatus } from "react-dom";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Separator } from "@/components/ui/separator";
import { FileSpreadsheet, Info, Upload, CheckCircle2, XCircle, Loader2, Sparkles } from "lucide-react";
import { importCsvAction, loadDemoDatasetAction } from "@/lib/actions/import-action";
import { initialImportState } from "@/lib/actions/import-types";

function CsvBtn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Upload className="h-4 w-4 mr-2" />}
            {pending ? "Bezig met importeren..." : "Upload en importeer"}
        </Button>
    );
}

function DemoBtn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" variant="outline" className="w-full" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Sparkles className="h-4 w-4 mr-2" />}
            {pending ? "Bezig met genereren..." : "Laad demo dataset (1000 medewerkers)"}
        </Button>
    );
}

export default function ImportForm({ accountSlug }: { accountSlug: string }) {
    const boundCsv = importCsvAction.bind(null, accountSlug);
    const boundDemo = loadDemoDatasetAction.bind(null, accountSlug);
    const [csvState, csvAction] = useFormState(boundCsv, initialImportState);
    const [demoState, demoAction] = useFormState(boundDemo, initialImportState);
    const state = csvState.result || csvState.error ? csvState : demoState;

    useEffect(() => {
        if (state.result && state.result.created > 0) {
            toast.success(`${state.result.created} contract${state.result.created === 1 ? "" : "en"} geïmporteerd`);
        }
        if (state.error) {
            toast.error(state.error);
        }
    }, [state]);

    return (
        <>
            {state.result && (
                <Alert className="mb-4">
                    <CheckCircle2 className="h-4 w-4" />
                    <AlertTitle>Import compleet</AlertTitle>
                    <AlertDescription>
                        {state.result.created} contract{state.result.created !== 1 ? "en" : ""} aangemaakt · {state.result.skipped} overgeslagen
                        {state.result.errors.length > 0 && (
                            <div className="mt-2 text-xs">
                                <strong>Fouten (eerste {Math.min(5, state.result.errors.length)}):</strong>
                                <ul className="list-disc list-inside mt-1">
                                    {state.result.errors.slice(0, 5).map((e, i) => (
                                        <li key={i}>{e}</li>
                                    ))}
                                </ul>
                            </div>
                        )}
                    </AlertDescription>
                </Alert>
            )}
            {state.error && (
                <Alert variant="destructive" className="mb-4">
                    <XCircle className="h-4 w-4" />
                    <AlertTitle>Fout</AlertTitle>
                    <AlertDescription>{state.error}</AlertDescription>
                </Alert>
            )}

            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <FileSpreadsheet className="h-5 w-5" />
                        CSV upload
                        <Badge variant="secondary">Beschikbaar</Badge>
                    </CardTitle>
                </CardHeader>
                <CardContent className="space-y-6">
                    <form action={csvAction} className="space-y-4">
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

                        <CsvBtn />
                    </form>

                    <div className="flex items-center gap-2">
                        <Separator className="flex-1" />
                        <span className="text-xs text-muted-foreground uppercase tracking-wide">of</span>
                        <Separator className="flex-1" />
                    </div>

                    <form action={demoAction} className="space-y-3">
                        <p className="text-sm text-muted-foreground">
                            Wil je eerst even spelen? Laad een gegenereerde populatie met 1000 medewerkers
                            (Belgische namen, 5 teams, realistische salaris- en opleidingsdistributie). Handig voor
                            demo&apos;s en performance-checks.
                        </p>
                        <DemoBtn />
                    </form>
                </CardContent>
            </Card>
        </>
    );
}
