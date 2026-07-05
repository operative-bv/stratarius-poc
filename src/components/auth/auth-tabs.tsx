"use client";

import * as React from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/ui/submit-button";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { CheckCircle2, AlertTriangle, MailCheck } from "lucide-react";

type ServerAction = (prev: unknown, formData: FormData) => Promise<unknown>;

export default function AuthTabs({
    signIn,
    signUp,
    initialTab,
    kind,
    email,
    message,
}: {
    signIn: ServerAction;
    signUp: ServerAction;
    initialTab: "login" | "signup";
    kind?: string;
    email?: string;
    message?: string;
}) {
    return (
        <Tabs defaultValue={initialTab} className="w-full">
            <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="login">Inloggen</TabsTrigger>
                <TabsTrigger value="signup">Aanmaken</TabsTrigger>
            </TabsList>

            <TabsContent value="login" className="mt-4">
                <form className="flex flex-col gap-4">
                    <div className="grid gap-2">
                        <Label htmlFor="login-email">E-mailadres</Label>
                        <Input
                            id="login-email"
                            name="email"
                            type="email"
                            placeholder="jij@bedrijf.be"
                            required
                            defaultValue={email}
                            autoComplete="email"
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label htmlFor="login-password">Wachtwoord</Label>
                        <Input
                            id="login-password"
                            name="password"
                            type="password"
                            required
                            autoComplete="current-password"
                        />
                    </div>
                    <SubmitButton formAction={signIn} pendingText="Bezig met inloggen...">
                        Log in
                    </SubmitButton>

                    {kind === "email_not_confirmed" && (
                        <Alert className="border-amber-500/40 bg-amber-500/5">
                            <AlertTriangle className="h-4 w-4 text-amber-600" />
                            <AlertTitle>Nog niet bevestigd</AlertTitle>
                            <AlertDescription>
                                Je e-mailadres <span className="font-medium">{email}</span> is nog niet bevestigd.
                                Check je inbox voor de bevestigingslink.
                            </AlertDescription>
                        </Alert>
                    )}
                    {kind === "invalid_credentials" && (
                        <Alert variant="destructive">
                            <AlertTriangle className="h-4 w-4" />
                            <AlertTitle>Ongeldige inloggegevens</AlertTitle>
                            <AlertDescription>
                                Het e-mailadres of wachtwoord klopt niet. Nog geen account? Wissel bovenaan naar
                                &quot;Aanmaken&quot;.
                            </AlertDescription>
                        </Alert>
                    )}
                    {kind === "error" && message && (
                        <Alert variant="destructive">
                            <AlertTriangle className="h-4 w-4" />
                            <AlertTitle>Er ging iets mis</AlertTitle>
                            <AlertDescription className="font-mono text-xs break-all">{message}</AlertDescription>
                        </Alert>
                    )}
                </form>
            </TabsContent>

            <TabsContent value="signup" className="mt-4">
                <form className="flex flex-col gap-4">
                    <div className="grid gap-2">
                        <Label htmlFor="signup-email">E-mailadres</Label>
                        <Input
                            id="signup-email"
                            name="email"
                            type="email"
                            placeholder="jij@bedrijf.be"
                            required
                            defaultValue={email}
                            autoComplete="email"
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label htmlFor="signup-password">Wachtwoord</Label>
                        <Input
                            id="signup-password"
                            name="password"
                            type="password"
                            required
                            minLength={8}
                            autoComplete="new-password"
                        />
                        <p className="text-xs text-muted-foreground">Minimaal 8 tekens.</p>
                    </div>
                    <SubmitButton formAction={signUp} variant="default" pendingText="Bezig met aanmaken...">
                        Account aanmaken
                    </SubmitButton>

                    {kind === "email_sent" && (
                        <Alert className="border-emerald-500/40 bg-emerald-500/5">
                            <MailCheck className="h-4 w-4 text-emerald-600" />
                            <AlertTitle>Bevestigingslink verstuurd</AlertTitle>
                            <AlertDescription>
                                We stuurden een link naar <span className="font-medium">{email}</span>. Klik &apos;m om
                                je account te activeren.
                            </AlertDescription>
                        </Alert>
                    )}
                    {kind === "user_exists" && (
                        <Alert className="border-blue-500/40 bg-blue-500/5">
                            <CheckCircle2 className="h-4 w-4 text-blue-600" />
                            <AlertTitle>Account bestaat al</AlertTitle>
                            <AlertDescription>
                                Er is al een account voor <span className="font-medium">{email}</span>. Wissel bovenaan
                                naar &quot;Inloggen&quot;.
                            </AlertDescription>
                        </Alert>
                    )}
                </form>
            </TabsContent>
        </Tabs>
    );
}
