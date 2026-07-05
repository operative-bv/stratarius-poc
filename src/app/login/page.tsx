import Link from "next/link";
import { headers } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { SubmitButton } from "@/components/ui/submit-button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { CheckCircle2, AlertTriangle, MailCheck } from "lucide-react";

export default function Login({
    searchParams,
}: {
    searchParams: { message?: string; returnUrl?: string; email?: string; kind?: string };
}) {
    const signIn = async (_prevState: unknown, formData: FormData) => {
        "use server";

        const email = formData.get("email") as string;
        const password = formData.get("password") as string;
        const supabase = createClient();

        const signInReturnUrl =
            searchParams.returnUrl && searchParams.returnUrl !== "undefined"
                ? searchParams.returnUrl
                : null;
        const { error } = await supabase.auth.signInWithPassword({ email, password });

        if (error) {
            console.error("[signIn] Supabase auth error:", error.status, error.code, error.message);
            const returnUrlParam = signInReturnUrl ? `&returnUrl=${encodeURIComponent(signInReturnUrl)}` : "";
            if (error.code === "email_not_confirmed") {
                return redirect(`/login?kind=email_not_confirmed&email=${encodeURIComponent(email)}${returnUrlParam}`);
            }
            if (error.code === "invalid_credentials") {
                return redirect(`/login?kind=invalid_credentials${returnUrlParam}`);
            }
            const detail = `${error.status ?? "?"} ${error.code ?? "?"}: ${error.message}`;
            return redirect(`/login?kind=error&message=${encodeURIComponent(detail)}${returnUrlParam}`);
        }

        const target =
            searchParams.returnUrl && searchParams.returnUrl !== "undefined"
                ? searchParams.returnUrl
                : "/dashboard";
        return redirect(target);
    };

    const signUp = async (_prevState: unknown, formData: FormData) => {
        "use server";

        const origin = process.env.NEXT_PUBLIC_URL ?? headers().get("origin");
        const email = formData.get("email") as string;
        const password = formData.get("password") as string;
        const supabase = createClient();

        const rawReturnUrl = searchParams.returnUrl;
        const safeReturnUrl = rawReturnUrl && rawReturnUrl !== "undefined" ? rawReturnUrl : "";
        const redirectQuery = safeReturnUrl ? `?returnUrl=${encodeURIComponent(safeReturnUrl)}` : "";

        const { error } = await supabase.auth.signUp({
            email,
            password,
            options: { emailRedirectTo: `${origin}/auth/callback${redirectQuery}` },
        });

        if (error) {
            const errorReturnUrl = safeReturnUrl ? `&returnUrl=${encodeURIComponent(safeReturnUrl)}` : "";
            if (error.code === "user_already_exists" || error.code === "user_repeated_signup") {
                return redirect(`/login?kind=user_exists&email=${encodeURIComponent(email)}${errorReturnUrl}`);
            }
            return redirect(`/login?kind=error&message=${encodeURIComponent(error.message)}${errorReturnUrl}`);
        }

        return redirect(`/login?kind=email_sent&email=${encodeURIComponent(email)}`);
    };

    return (
        <div className="flex min-h-svh w-full items-center justify-center p-6 md:p-10">
            <div className="w-full max-w-sm">
                <div className="flex flex-col gap-6">
                    <Card>
                        <CardHeader className="text-center">
                            <Link href="/" className="mx-auto flex h-10 w-10 items-center justify-center rounded-md bg-primary text-primary-foreground font-bold text-lg">
                                S
                            </Link>
                            <CardTitle className="text-xl mt-2">Welkom bij Stratarius</CardTitle>
                            <CardDescription>
                                Log in met je e-mailadres, of maak een nieuw account aan
                            </CardDescription>
                        </CardHeader>
                        <CardContent>
                            <form className="flex flex-col gap-4">
                                <div className="grid gap-2">
                                    <Label htmlFor="email">E-mailadres</Label>
                                    <Input
                                        id="email"
                                        name="email"
                                        type="email"
                                        placeholder="jij@bedrijf.be"
                                        required
                                        defaultValue={searchParams.email}
                                    />
                                </div>
                                <div className="grid gap-2">
                                    <Label htmlFor="password">Wachtwoord</Label>
                                    <Input id="password" name="password" type="password" required />
                                </div>
                                <SubmitButton formAction={signIn} pendingText="Bezig met inloggen...">
                                    Log in
                                </SubmitButton>
                                <SubmitButton formAction={signUp} variant="outline" pendingText="Bezig met aanmaken...">
                                    Nieuw account
                                </SubmitButton>

                                {searchParams?.kind === "email_sent" && (
                                    <Alert className="border-emerald-500/40 bg-emerald-500/5">
                                        <MailCheck className="h-4 w-4 text-emerald-600" />
                                        <AlertTitle>Bevestigingslink verstuurd</AlertTitle>
                                        <AlertDescription>
                                            We stuurden een link naar <span className="font-medium">{searchParams.email}</span>. Klik &apos;m om je account te activeren.
                                        </AlertDescription>
                                    </Alert>
                                )}
                                {searchParams?.kind === "email_not_confirmed" && (
                                    <Alert className="border-amber-500/40 bg-amber-500/5">
                                        <AlertTriangle className="h-4 w-4 text-amber-600" />
                                        <AlertTitle>Nog niet bevestigd</AlertTitle>
                                        <AlertDescription>
                                            Je e-mailadres <span className="font-medium">{searchParams.email}</span> is nog niet bevestigd. Check je inbox voor de bevestigingslink.
                                        </AlertDescription>
                                    </Alert>
                                )}
                                {searchParams?.kind === "invalid_credentials" && (
                                    <Alert variant="destructive">
                                        <AlertTriangle className="h-4 w-4" />
                                        <AlertTitle>Ongeldige inloggegevens</AlertTitle>
                                        <AlertDescription>
                                            Het e-mailadres of wachtwoord klopt niet. Nog geen account? Klik op &quot;Nieuw account&quot;.
                                        </AlertDescription>
                                    </Alert>
                                )}
                                {searchParams?.kind === "user_exists" && (
                                    <Alert className="border-blue-500/40 bg-blue-500/5">
                                        <CheckCircle2 className="h-4 w-4 text-blue-600" />
                                        <AlertTitle>Account bestaat al</AlertTitle>
                                        <AlertDescription>
                                            Er is al een account voor <span className="font-medium">{searchParams.email}</span>. Log gewoon in.
                                        </AlertDescription>
                                    </Alert>
                                )}
                                {searchParams?.kind === "error" && searchParams?.message && (
                                    <Alert variant="destructive">
                                        <AlertTriangle className="h-4 w-4" />
                                        <AlertTitle>Er ging iets mis</AlertTitle>
                                        <AlertDescription className="font-mono text-xs break-all">
                                            {searchParams.message}
                                        </AlertDescription>
                                    </Alert>
                                )}
                            </form>
                        </CardContent>
                    </Card>
                    <div className="text-center text-xs text-muted-foreground">
                        Belgische loonkost-cascade en loonkloof-analyse
                    </div>
                </div>
            </div>
        </div>
    );
}
