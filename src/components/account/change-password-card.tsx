"use client";

import { useEffect } from "react";
import { useFormState, useFormStatus } from "react-dom";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";
import { changePassword } from "@/lib/actions/account-security";
import { initialAccountActionState } from "@/lib/actions/account-security-types";

function Btn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" disabled={pending}>
            {pending && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
            {pending ? "Bijwerken..." : "Wachtwoord wijzigen"}
        </Button>
    );
}

export default function ChangePasswordCard() {
    const [state, formAction] = useFormState(changePassword, initialAccountActionState);

    useEffect(() => {
        if (state.status === "success") toast.success(state.message);
        else if (state.status === "error") toast.error(state.message);
    }, [state]);

    return (
        <Card>
            <CardHeader>
                <CardTitle>Wachtwoord wijzigen</CardTitle>
                <CardDescription>
                    Kies een nieuw wachtwoord van minstens 8 tekens
                </CardDescription>
            </CardHeader>
            <form action={formAction}>
                <CardContent className="flex flex-col gap-y-4">
                    <div className="flex flex-col gap-y-2">
                        <Label htmlFor="password">Nieuw wachtwoord</Label>
                        <Input
                            type="password"
                            name="password"
                            id="password"
                            placeholder="Minimaal 8 tekens"
                            minLength={8}
                            required
                            autoComplete="new-password"
                        />
                    </div>
                    <div className="flex flex-col gap-y-2">
                        <Label htmlFor="confirm">Herhaal nieuw wachtwoord</Label>
                        <Input
                            type="password"
                            name="confirm"
                            id="confirm"
                            placeholder="Nogmaals ter bevestiging"
                            minLength={8}
                            required
                            autoComplete="new-password"
                        />
                    </div>
                </CardContent>
                <CardFooter>
                    <Btn />
                </CardFooter>
            </form>
        </Card>
    );
}
