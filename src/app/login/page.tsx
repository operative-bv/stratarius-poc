import Link from "next/link";
import { headers } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import AuthTabs from "@/components/auth/auth-tabs";

const SIGNUP_KINDS = new Set(["email_sent", "user_exists"]);

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

    const initialTab: "login" | "signup" =
        searchParams.kind && SIGNUP_KINDS.has(searchParams.kind) ? "signup" : "login";

    return (
        <div className="flex min-h-svh w-full items-center justify-center p-6 md:p-10">
            <div className="w-full max-w-sm">
                <div className="flex flex-col gap-6">
                    <Card>
                        <CardHeader className="text-center">
                            <Link
                                href="/"
                                className="mx-auto flex h-10 w-10 items-center justify-center rounded-md bg-primary text-primary-foreground font-bold text-lg"
                            >
                                S
                            </Link>
                            <CardTitle className="text-xl mt-2">Welkom bij Stratarius</CardTitle>
                            <CardDescription>Belgische loonkost-cascade en loonkloof-analyse</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <AuthTabs
                                signIn={signIn}
                                signUp={signUp}
                                initialTab={initialTab}
                                kind={searchParams.kind}
                                email={searchParams.email}
                                message={searchParams.message}
                            />
                        </CardContent>
                    </Card>
                    <div className="text-center text-xs text-muted-foreground text-balance">
                        Door verder te gaan ga je akkoord met onze voorwaarden en het privacybeleid.
                    </div>
                </div>
            </div>
        </div>
    );
}
