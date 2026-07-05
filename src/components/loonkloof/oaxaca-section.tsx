"use client";

import { useFormState, useFormStatus } from "react-dom";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { RefreshCw, Sigma } from "lucide-react";
import { runOaxacaAction } from "@/lib/actions/oaxaca-action";
import { initialOaxacaState } from "@/lib/actions/oaxaca-types";
import type { OaxacaResult } from "@/lib/oaxaca-client";

function fmtEur(v: number): string {
    return v.toLocaleString("nl-BE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function RunButton({ label, variant = "default", size = "default" }: {
    label: string;
    variant?: "default" | "outline" | "ghost";
    size?: "default" | "sm";
}) {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" variant={variant} size={size} disabled={pending}>
            {pending ? <RefreshCw className="h-4 w-4 mr-2 animate-spin" /> : <Sigma className="h-4 w-4 mr-2" />}
            {pending ? "Berekent..." : label}
        </Button>
    );
}

export default function OaxacaSection() {
    const [state, formAction] = useFormState(runOaxacaAction, initialOaxacaState);
    const result = state.result;
    const error = state.error;

    return (
        <Card>
            <CardHeader>
                <CardTitle className="flex items-center gap-2">
                    <Sigma className="h-5 w-5" />
                    Oaxaca-Blinder regressie
                    <Badge variant="outline" className="text-xs font-normal">
                        Statistisch model
                    </Badge>
                </CardTitle>
            </CardHeader>
            <CardContent>
                {!result && !error && (
                    <form action={formAction} className="space-y-4">
                        <p className="text-sm text-muted-foreground">
                            Diepgaande analyse per variabele met coëfficiënten en significantie. Draait in een
                            beveiligde omgeving binnen de EU.
                        </p>
                        <RunButton label="Run Oaxaca-Blinder" />
                    </form>
                )}
                {error && (
                    <div className="rounded-lg border border-red-500/40 bg-red-50 dark:bg-red-950/20 p-4">
                        <div className="text-sm font-semibold text-red-700 dark:text-red-400">Service error</div>
                        <p className="text-xs mt-1 font-mono break-all">{error}</p>
                        <form action={formAction} className="mt-3">
                            <RunButton label="Opnieuw proberen" variant="outline" size="sm" />
                        </form>
                    </div>
                )}
                {result && <OaxacaResultView result={result} formAction={formAction} />}
            </CardContent>
        </Card>
    );
}

function OaxacaResultView({
    result,
    formAction,
}: {
    result: OaxacaResult;
    formAction: (formData: FormData) => void;
}) {
    const rawGap = Number(result.raw_gap);
    const endowment = Number(result.endowment_gap);
    const coefficient = Number(result.coefficient_gap);
    const totalAbs = Math.abs(endowment) + Math.abs(coefficient);
    const endowmentShare = totalAbs > 0 ? Math.abs(endowment) / totalAbs : 0;
    const coefficientShare = totalAbs > 0 ? Math.abs(coefficient) / totalAbs : 0;

    return (
        <div className="space-y-6">
            <div className="grid gap-4 md:grid-cols-3">
                <div className="rounded-lg border p-4 space-y-1">
                    <div className="text-xs uppercase text-muted-foreground">Ruwe kloof</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(rawGap))}</div>
                    <div className="text-xs text-muted-foreground">
                        n_M = {result.n_m} · n_V = {result.n_v}
                    </div>
                </div>
                <div className="rounded-lg border p-4 bg-blue-50 dark:bg-blue-950/20 space-y-1">
                    <div className="text-xs uppercase text-muted-foreground">Endowment</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(endowment))}</div>
                    <div className="text-xs text-muted-foreground">{(endowmentShare * 100).toFixed(0)}% via observables</div>
                </div>
                <div className="rounded-lg border p-4 bg-orange-50 dark:bg-orange-950/20 space-y-1">
                    <div className="text-xs uppercase text-muted-foreground">Coefficient (residual)</div>
                    <div className="text-2xl font-semibold tabular-nums">€ {fmtEur(Math.abs(coefficient))}</div>
                    <div className="text-xs text-muted-foreground">
                        {(coefficientShare * 100).toFixed(0)}% onverklaard door beloningsverschil
                    </div>
                </div>
            </div>

            <div>
                <div className="text-sm font-medium mb-2">Coëfficiënten per variabele</div>
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead>Variabele</TableHead>
                            <TableHead className="text-right">β mannen</TableHead>
                            <TableHead className="text-right">β vrouwen</TableHead>
                            <TableHead className="text-right">p-value</TableHead>
                            <TableHead className="text-right">Bijdrage kloof</TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {result.coefficients.map((c) => {
                            const isDropped = c.dropped === true;
                            const significant = c.p_value != null && c.p_value < 0.05;
                            return (
                                <TableRow key={c.variabele}>
                                    <TableCell className="font-medium">
                                        {c.variabele}
                                        {isDropped && (
                                            <span className="ml-2 text-xs text-muted-foreground italic">geen variatie in data</span>
                                        )}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums">{c.beta_m.toFixed(3)}</TableCell>
                                    <TableCell className="text-right tabular-nums">{c.beta_v.toFixed(3)}</TableCell>
                                    <TableCell
                                        className={`text-right tabular-nums ${significant ? "font-semibold" : "text-muted-foreground"}`}
                                    >
                                        {c.p_value == null ? "n.v.t." : c.p_value.toFixed(3)}
                                        {significant && " *"}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums">€ {fmtEur(Math.abs(c.kloof_bijdrage))}</TableCell>
                                </TableRow>
                            );
                        })}
                    </TableBody>
                </Table>
                <p className="text-xs text-muted-foreground mt-2">
                    * p &lt; 0.05 = statistisch significant. R² mannen = {result.r_squared_m.toFixed(2)} · R² vrouwen = {result.r_squared_v.toFixed(2)}.
                </p>
            </div>

            {result.note && (
                <div className="rounded-lg border border-blue-500/40 bg-blue-50 dark:bg-blue-950/20 p-3 text-xs">
                    <strong>Methode:</strong> {result.note}
                </div>
            )}

            <div className="flex items-center justify-between text-xs text-muted-foreground">
                <div>Grondslag: {result.rechtsgrondslag ?? "—"}</div>
                <form action={formAction}>
                    <RunButton label="Herbereken" variant="ghost" size="sm" />
                </form>
            </div>
        </div>
    );
}
