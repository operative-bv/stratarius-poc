"use client";

import { useFormState, useFormStatus } from "react-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Building2, Info, Check, Loader2 } from "lucide-react";
import { completeSetupAction } from "@/lib/actions/setup-action";
import { initialSetupState } from "@/lib/actions/setup-types";

function SubmitBtn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" size="lg" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Check className="h-4 w-4 mr-2" />}
            {pending ? "Bezig met opzetten..." : "Setup afronden en naar dashboard"}
        </Button>
    );
}

export default function SetupForm({
    accountSlug,
    accountId,
    defaultNaam,
}: {
    accountSlug: string;
    accountId: string;
    defaultNaam: string;
}) {
    const boundAction = completeSetupAction.bind(null, accountSlug);
    const [state, formAction] = useFormState(boundAction, initialSetupState);

    return (
        <>
            {state.error && (
                <Alert variant="destructive" className="mb-6">
                    <AlertTitle>Er ging iets mis</AlertTitle>
                    <AlertDescription>{state.error}</AlertDescription>
                </Alert>
            )}

            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Building2 className="h-5 w-5" />
                        Organisatie configuratie
                    </CardTitle>
                    <CardDescription>
                        Deze gegevens sturen de rekencascade — je kunt ze later aanpassen via Settings.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <form action={formAction} className="space-y-5">
                        <input type="hidden" name="account_id" value={accountId} />

                        <div className="space-y-2">
                            <Label htmlFor="naam">Naam legale entiteit</Label>
                            <Input
                                id="naam"
                                name="naam"
                                defaultValue={defaultNaam}
                                placeholder="bv. Operative BVBA"
                                required
                            />
                            <p className="text-xs text-muted-foreground">
                                Verschijnt op facturen, rapporten en het dashboard. Vaak dezelfde naam als je organisatie.
                            </p>
                        </div>

                        <div className="grid gap-4 md:grid-cols-2">
                            <div className="space-y-2">
                                <Label htmlFor="gewest">Gewest</Label>
                                <Select name="gewest" defaultValue="vlaanderen">
                                    <SelectTrigger id="gewest"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="vlaanderen">Vlaanderen</SelectItem>
                                        <SelectItem value="brussel">Brussel-Hoofdstad</SelectItem>
                                        <SelectItem value="wallonie">Wallonië</SelectItem>
                                    </SelectContent>
                                </Select>
                                <p className="text-xs text-muted-foreground">
                                    Bepaalt welke doelgroepverminderingen (VDAB / Actiris / Forem) van toepassing zijn.
                                </p>
                            </div>

                            <div className="space-y-2">
                                <Label htmlFor="werkgeverscategorie">Werkgeverscategorie</Label>
                                <Select name="werkgeverscategorie" defaultValue="1">
                                    <SelectTrigger id="werkgeverscategorie"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="1">1 — Algemeen</SelectItem>
                                        <SelectItem value="2">2 — Social profit</SelectItem>
                                        <SelectItem value="3">3 — Beschutte werkplaats</SelectItem>
                                    </SelectContent>
                                </Select>
                                <p className="text-xs text-muted-foreground">
                                    Beïnvloedt RSZ-tarief (cat 1: 25.07% · cat 2: 24.32% · cat 3: 17.07%).
                                </p>
                            </div>
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="ondernemingsnr">Ondernemingsnummer (KBO) <span className="text-muted-foreground text-xs font-normal">— optioneel</span></Label>
                            <Input
                                id="ondernemingsnr"
                                name="ondernemingsnr"
                                placeholder="0123.456.789"
                                pattern="^[01]\d{3}\.\d{3}\.\d{3}$"
                            />
                            <p className="text-xs text-muted-foreground">
                                Formaat 0XXX.XXX.XXX. Nodig voor DmfA-aangifte en fiscaal rapporteren, niet voor de POC-berekeningen.
                            </p>
                        </div>

                        <Alert>
                            <Info className="h-4 w-4" />
                            <AlertTitle>Wat gebeurt hierna</AlertTitle>
                            <AlertDescription className="text-xs">
                                We maken je organisatie aan en een basisscenario waar al je contracten standaard onder
                                vallen. Daarna kun je meteen medewerkers importeren via CSV of handmatig toevoegen.
                            </AlertDescription>
                        </Alert>

                        <SubmitBtn />
                    </form>
                </CardContent>
            </Card>
        </>
    );
}
