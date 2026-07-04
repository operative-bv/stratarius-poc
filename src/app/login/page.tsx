import Link from "next/link";
import { headers } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { SubmitButton } from "@/components/ui/submit-button";
import { Input } from "@/components/ui/input";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { CheckCircle2, AlertTriangle, MailCheck } from "lucide-react";

export default function Login({
  searchParams,
}: {
  searchParams: { message?: string; returnUrl?: string; email?: string; kind?: string };
}) {
  const signIn = async (_prevState: any, formData: FormData) => {
    "use server";

    const email = formData.get("email") as string;
    const password = formData.get("password") as string;
    const supabase = createClient();

    const signInReturnUrl = searchParams.returnUrl && searchParams.returnUrl !== "undefined"
      ? searchParams.returnUrl : null;
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (error) {
      console.error("[signIn] Supabase auth error:", error.status, error.code, error.message);
      const returnUrlParam = signInReturnUrl ? `&returnUrl=${encodeURIComponent(signInReturnUrl)}` : "";
      // Specifieke boodschap voor niet-bevestigd account (Supabase code = 'email_not_confirmed').
      if (error.code === "email_not_confirmed") {
        return redirect(`/login?kind=email_not_confirmed&email=${encodeURIComponent(email)}${returnUrlParam}`);
      }
      // Ongeldige credentials — geen technische details voor de user tonen.
      if (error.code === "invalid_credentials") {
        return redirect(`/login?kind=invalid_credentials${returnUrlParam}`);
      }
      // Anders: technische fallback (bv. 500).
      const detail = `${error.status ?? "?"} ${error.code ?? "?"}: ${error.message}`;
      return redirect(`/login?kind=error&message=${encodeURIComponent(detail)}${returnUrlParam}`);
    }

    const target = searchParams.returnUrl && searchParams.returnUrl !== "undefined"
      ? searchParams.returnUrl : "/dashboard";
    return redirect(target);
  };

  const signUp = async (_prevState: any, formData: FormData) => {
    "use server";

    const origin = process.env.NEXT_PUBLIC_URL ?? headers().get("origin");
    const email = formData.get("email") as string;
    const password = formData.get("password") as string;
    const supabase = createClient();

    // Alleen returnUrl mee-geven als 'ie echt is gezet (voorkomt "returnUrl=undefined" string).
    const rawReturnUrl = searchParams.returnUrl;
    const safeReturnUrl = rawReturnUrl && rawReturnUrl !== "undefined" ? rawReturnUrl : "";
    const redirectQuery = safeReturnUrl ? `?returnUrl=${encodeURIComponent(safeReturnUrl)}` : "";

    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${origin}/auth/callback${redirectQuery}`,
      },
    });

    if (error) {
      const errorReturnUrl = safeReturnUrl ? `&returnUrl=${encodeURIComponent(safeReturnUrl)}` : "";
      // Al bestaand account? Supabase geeft user_already_exists / user_repeated_signup.
      if (error.code === "user_already_exists" || error.code === "user_repeated_signup") {
        return redirect(`/login?kind=user_exists&email=${encodeURIComponent(email)}${errorReturnUrl}`);
      }
      return redirect(`/login?kind=error&message=${encodeURIComponent(error.message)}${errorReturnUrl}`);
    }

    return redirect(`/login?kind=email_sent&email=${encodeURIComponent(email)}`);
  };

  return (
    <div className="flex-1 flex flex-col w-full px-8 sm:max-w-md justify-center gap-2">
      <Link
        href="/"
        className="absolute left-8 top-8 py-2 px-4 rounded-md no-underline text-foreground bg-btn-background hover:bg-btn-background-hover flex items-center group text-sm"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="mr-2 h-4 w-4 transition-transform group-hover:-translate-x-1"
        >
          <polyline points="15 18 9 12 15 6" />
        </svg>{" "}
        Back
      </Link>

      <form className="animate-in flex-1 flex flex-col w-full justify-center gap-2 text-foreground">
        <label className="text-md" htmlFor="email">
          Email
        </label>
        <Input
          name="email"
          placeholder="you@example.com"
          required
        />
        <label className="text-md" htmlFor="password">
          Password
        </label>
        <Input
          type="password"
          name="password"
          placeholder="••••••••"
          required
        />
        <SubmitButton
          formAction={signIn}
          pendingText="Signing In..."
        >
          Sign In
        </SubmitButton>
        <SubmitButton
          formAction={signUp}
          variant="outline"
          pendingText="Signing Up..."
        >
          Sign Up
        </SubmitButton>
        {searchParams?.kind === "email_sent" && (
          <Alert className="mt-4 border-emerald-500/40 bg-emerald-500/5">
            <MailCheck className="h-4 w-4 text-emerald-600" />
            <AlertTitle>Bevestigingslink verstuurd</AlertTitle>
            <AlertDescription>
              We stuurden een link naar <span className="font-medium">{searchParams.email}</span>. Klik &apos;m om je account te activeren.
            </AlertDescription>
          </Alert>
        )}
        {searchParams?.kind === "email_not_confirmed" && (
          <Alert className="mt-4 border-amber-500/40 bg-amber-500/5">
            <AlertTriangle className="h-4 w-4 text-amber-600" />
            <AlertTitle>Nog niet bevestigd</AlertTitle>
            <AlertDescription>
              Je e-mailadres <span className="font-medium">{searchParams.email}</span> is nog niet bevestigd. Check je inbox voor de bevestigingslink.
            </AlertDescription>
          </Alert>
        )}
        {searchParams?.kind === "invalid_credentials" && (
          <Alert variant="destructive" className="mt-4">
            <AlertTriangle className="h-4 w-4" />
            <AlertTitle>Ongeldige inloggegevens</AlertTitle>
            <AlertDescription>
              Het e-mailadres of wachtwoord klopt niet. Nog geen account? Klik hieronder op Sign Up.
            </AlertDescription>
          </Alert>
        )}
        {searchParams?.kind === "user_exists" && (
          <Alert className="mt-4 border-blue-500/40 bg-blue-500/5">
            <CheckCircle2 className="h-4 w-4 text-blue-600" />
            <AlertTitle>Account bestaat al</AlertTitle>
            <AlertDescription>
              Er is al een account voor <span className="font-medium">{searchParams.email}</span>. Log in met Sign In hierboven.
            </AlertDescription>
          </Alert>
        )}
        {searchParams?.kind === "error" && searchParams?.message && (
          <Alert variant="destructive" className="mt-4">
            <AlertTriangle className="h-4 w-4" />
            <AlertTitle>Er ging iets mis</AlertTitle>
            <AlertDescription className="font-mono text-xs break-all">
              {searchParams.message}
            </AlertDescription>
          </Alert>
        )}
      </form>
    </div>
  );
}
