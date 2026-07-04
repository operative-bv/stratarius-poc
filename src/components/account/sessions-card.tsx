"use client";

import { useEffect } from "react";
import { useFormState, useFormStatus } from "react-dom";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";
import { signOutOtherSessions, initialAccountActionState } from "@/lib/actions/account-security";

function Btn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" variant="outline" disabled={pending}>
            {pending && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
            {pending ? "Uitloggen..." : "Log uit op andere apparaten"}
        </Button>
    );
}

export default function SessionsCard() {
    const [state, formAction] = useFormState(signOutOtherSessions, initialAccountActionState);

    useEffect(() => {
        if (state.ok === true && state.message) toast.success(state.message);
        if (state.ok === false && state.message) toast.error(state.message);
    }, [state]);

    return (
        <Card>
            <CardHeader>
                <CardTitle>Actieve sessies</CardTitle>
                <CardDescription>
                    Log uit op alle andere apparaten. Handig als je een device
                    kwijt bent of vermoedt dat iemand anders is ingelogd. Je
                    huidige sessie blijft actief.
                </CardDescription>
            </CardHeader>
            <form action={formAction}>
                <CardContent className="text-sm text-muted-foreground">
                    Deze actie invalideert refresh tokens op alle andere devices.
                    Je moet daar opnieuw inloggen om verder te gaan.
                </CardContent>
                <CardFooter>
                    <Btn />
                </CardFooter>
            </form>
        </Card>
    );
}
