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
import { FileSpreadsheet, Info, Upload, CheckCircle2, XCircle, Loader2 } from "lucide-react";
import { importCsvAction } from "@/lib/actions/import-action";
import { initialImportState } from "@/lib/actions/import-types";

function Btn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Upload className="h-4 w-4 mr-2" />}
            {pending ? "Bezig met importeren..." : "Upload en importeer"}
        </Button>
    );
}

export default function ImportForm({ accountSlug }: { accountSlug: string }) {
    const bound = importCsvAction.bind(null, accountSlug);
    const [state, formAction] = useFormState(bound, initialImportState);

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
                <CardContent>
                    <form action={formAction} className="space-y-4">
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

                        <Btn />
                    </form>
                </CardContent>
            </Card>
        </>
    );
}
