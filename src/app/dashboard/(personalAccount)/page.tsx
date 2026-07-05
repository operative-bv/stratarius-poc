import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/dashboard/page-header";
import { Home, Building2, ArrowRight, Plus, Sparkles } from "lucide-react";
import Link from "next/link";

type TeamAccount = {
    account_id: string;
    account_role: string;
    is_primary_owner: boolean;
    name: string;
    slug: string;
    personal_account: boolean;
};

export default async function PersonalAccountPage() {
    const supabase = createClient();
    const { data: personalAccount } = await supabase.rpc("get_personal_account");
    const { data: accountsData } = await supabase.rpc("get_accounts");
    const teams = ((accountsData ?? []) as TeamAccount[]).filter((a) => !a.personal_account);

    return (
        <div className="mx-auto max-w-4xl space-y-6">
            <PageHeader
                icon={Home}
                title={`Welkom, ${personalAccount?.name ?? "gebruiker"}`}
                description="Kies een organisatie om verder te gaan, of maak een nieuwe aan."
            />

            {teams.length > 0 ? (
                <div className="grid gap-4 md:grid-cols-2">
                    {teams.map((team) => (
                        <Link key={team.account_id} href={`/dashboard/${team.slug}`}>
                            <Card className="hover:border-primary/40 hover:shadow-sm transition-all cursor-pointer group h-full">
                                <CardHeader>
                                    <CardTitle className="flex items-center gap-2">
                                        <Building2 className="h-5 w-5 text-muted-foreground" />
                                        {team.name}
                                    </CardTitle>
                                </CardHeader>
                                <CardContent>
                                    <div className="flex items-center justify-between">
                                        <div className="text-xs text-muted-foreground">
                                            Rol: <span className="font-medium">{team.account_role}</span>
                                            {team.is_primary_owner && " · owner"}
                                        </div>
                                        <ArrowRight className="h-4 w-4 text-muted-foreground group-hover:translate-x-1 group-hover:text-foreground transition-all" />
                                    </div>
                                </CardContent>
                            </Card>
                        </Link>
                    ))}
                </div>
            ) : (
                <Card>
                    <CardContent className="pt-6 text-center space-y-4">
                        <Sparkles className="h-8 w-8 mx-auto text-muted-foreground" />
                        <div className="space-y-1">
                            <p className="text-sm font-medium">Nog geen organisatie</p>
                            <p className="text-xs text-muted-foreground">
                                Maak je eerste organisatie aan om de cascade te gebruiken.
                            </p>
                        </div>
                    </CardContent>
                </Card>
            )}

            <Card>
                <CardHeader>
                    <CardTitle className="text-base">Snel</CardTitle>
                </CardHeader>
                <CardContent className="flex flex-col sm:flex-row gap-2">
                    <Button asChild variant="outline">
                        <Link href="/dashboard/settings/teams">
                            <Plus className="h-4 w-4 mr-2" />
                            Nieuwe organisatie
                        </Link>
                    </Button>
                    <Button asChild variant="outline">
                        <Link href="/dashboard/settings">
                            Profiel bewerken
                        </Link>
                    </Button>
                </CardContent>
            </Card>
        </div>
    );
}
