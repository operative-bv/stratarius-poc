"use client";

import { useEffect } from "react";
import { useFormState, useFormStatus } from "react-dom";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Car, Percent, AlertTriangle, Loader2 } from "lucide-react";
import { createScenarioAction, createWagenScenarioAction } from "@/lib/actions/scenarios-actions";
import { initialScenarioState, type ScenarioState } from "@/lib/actions/scenarios-types";

type Scenario = { scenario_id: string; naam: string; kind: string; created_at: string };
type Functie = { functie_id: string; functienaam: string };

function SubmitBtn({ label, variant = "default", icon }: {
    label: string;
    variant?: "default" | "outline";
    icon?: React.ReactNode;
}) {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" variant={variant} disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : icon}
            {pending ? "Bezig..." : label}
        </Button>
    );
}

function useScenarioFeedback(state: ScenarioState) {
    const router = useRouter();
    useEffect(() => {
        if (state.redirectTo) {
            if (state.successMessage) toast.success(state.successMessage);
            router.push(state.redirectTo);
        }
    }, [state, router]);
}

export default function ScenariosTabs({
    accountSlug,
    entiteitId,
    baselineId,
    scenarios,
    functies,
}: {
    accountSlug: string;
    entiteitId: string;
    baselineId?: string;
    scenarios: Scenario[];
    functies: Functie[];
}) {
    const boundLoon = createScenarioAction.bind(null, accountSlug);
    const boundWagen = createWagenScenarioAction.bind(null, accountSlug);
    const [loonState, loonAction] = useFormState(boundLoon, initialScenarioState);
    const [wagenState, wagenAction] = useFormState(boundWagen, initialScenarioState);

    useScenarioFeedback(loonState);
    useScenarioFeedback(wagenState);

    return (
        <Tabs defaultValue="loon" className="w-full">
            <TabsList className="grid w-full grid-cols-2 max-w-md">
                <TabsTrigger value="loon" className="flex items-center gap-2">
                    <Percent className="h-4 w-4" />
                    Loon-mutatie
                </TabsTrigger>
                <TabsTrigger value="wagen" className="flex items-center gap-2">
                    <Car className="h-4 w-4" />
                    Wagen-toewijzing
                </TabsTrigger>
            </TabsList>

            <TabsContent value="loon" className="mt-4">
                <Card>
                    <CardHeader>
                        <CardTitle>Loon-mutatie scenario</CardTitle>
                    </CardHeader>
                    <CardContent>
                        {loonState.error && (
                            <Alert variant="destructive" className="mb-4">
                                <AlertTriangle className="h-4 w-4" />
                                <AlertTitle>Scenario niet aangemaakt</AlertTitle>
                                <AlertDescription>{loonState.error}</AlertDescription>
                            </Alert>
                        )}
                        <form action={loonAction} className="space-y-4">
                            <input type="hidden" name="entiteit" value={entiteitId} />

                            <div className="space-y-2">
                                <Label htmlFor="naam">Scenario naam</Label>
                                <Input id="naam" name="naam" placeholder="bv. Sales team krijgt bonus" required />
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="baseline">Baseline om te muteren</Label>
                                <Select name="baseline" defaultValue={baselineId}>
                                    <SelectTrigger id="baseline"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        {scenarios.map((s) => (
                                            <SelectItem key={s.scenario_id} value={s.scenario_id}>
                                                {s.naam}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="grid grid-cols-2 gap-3">
                                <div className="space-y-2">
                                    <Label htmlFor="mutatie_type">Mutatie type</Label>
                                    <Select name="mutatie_type" defaultValue="pct_increase">
                                        <SelectTrigger id="mutatie_type"><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                            <SelectItem value="pct_increase">Percentage (%)</SelectItem>
                                            <SelectItem value="flat_increase">Vast bedrag (+€)</SelectItem>
                                            <SelectItem value="flat_replace">Vervang basisloon (€)</SelectItem>
                                        </SelectContent>
                                    </Select>
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="mutatie_value">Waarde</Label>
                                    <Input id="mutatie_value" name="mutatie_value" type="number" step="0.01" placeholder="10" required />
                                </div>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="team">Toepassen op</Label>
                                <Select name="team" defaultValue="all">
                                    <SelectTrigger id="team"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="all">Alle medewerkers</SelectItem>
                                        {functies.map((f) => (
                                            <SelectItem key={f.functie_id} value={f.functie_id}>
                                                Alleen team {f.functienaam}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <SubmitBtn label="Maak scenario → open in populatie" />

                            <p className="text-xs text-muted-foreground">
                                Er wordt een nieuw scenario aangemaakt met aangepaste lonen. Je gaat direct naar de
                                populatie-vergelijking.
                            </p>
                        </form>
                    </CardContent>
                </Card>
            </TabsContent>

            <TabsContent value="wagen" className="mt-4">
                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Car className="h-5 w-5" />
                            Wagen-toewijzing scenario
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        {wagenState.error && (
                            <Alert variant="destructive" className="mb-4">
                                <AlertTriangle className="h-4 w-4" />
                                <AlertTitle>Wagen-scenario niet aangemaakt</AlertTitle>
                                <AlertDescription>{wagenState.error}</AlertDescription>
                            </Alert>
                        )}
                        <form action={wagenAction} className="space-y-4">
                            <input type="hidden" name="entiteit" value={entiteitId} />

                            <div className="space-y-2">
                                <Label htmlFor="wagen_naam">Scenario naam</Label>
                                <Input id="wagen_naam" name="naam" placeholder="bv. Sales team elektrische wagens" required />
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_baseline">Baseline</Label>
                                <Select name="baseline" defaultValue={baselineId}>
                                    <SelectTrigger id="wagen_baseline"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        {scenarios.filter((s) => s.kind === "baseline").map((s) => (
                                            <SelectItem key={s.scenario_id} value={s.scenario_id}>{s.naam}</SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_team">Team</Label>
                                <Select name="team" required>
                                    <SelectTrigger id="wagen_team"><SelectValue placeholder="Kies team" /></SelectTrigger>
                                    <SelectContent>
                                        {functies.map((f) => (
                                            <SelectItem key={f.functie_id} value={f.functie_id}>{f.functienaam}</SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="wagen_categorie">Wagen categorie</Label>
                                <Select name="wagen_categorie" defaultValue="electric">
                                    <SelectTrigger id="wagen_categorie"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="compact">Compact — €25k · €450/m · CO2 105</SelectItem>
                                        <SelectItem value="mid">Mid — €38k · €650/m · CO2 130</SelectItem>
                                        <SelectItem value="premium">Premium — €55k · €900/m · CO2 155</SelectItem>
                                        <SelectItem value="electric">Elektrisch — €45k · €700/m · CO2 0</SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>

                            <SubmitBtn label="Maak wagen-scenario" variant="outline" icon={<Car className="h-4 w-4 mr-2" />} />

                            <p className="text-xs text-muted-foreground">
                                Voegt patronale leasekost en fiscaal voordeel alle aard toe voor elk contract in het
                                gekozen team.
                            </p>
                        </form>
                    </CardContent>
                </Card>
            </TabsContent>
        </Tabs>
    );
}
