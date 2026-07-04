import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/server";
import { Mail } from "lucide-react";

export default async function AccountInfoCard() {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();

    return (
        <Card>
            <CardHeader>
                <CardTitle>Account</CardTitle>
                <CardDescription>Jouw inlog-informatie</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-y-3">
                <div className="flex flex-col gap-y-1">
                    <Label className="text-xs text-muted-foreground">E-mailadres</Label>
                    <div className="flex items-center gap-x-2 text-sm">
                        <Mail className="h-4 w-4 text-muted-foreground" />
                        <span>{user?.email ?? "—"}</span>
                    </div>
                </div>
                <div className="flex flex-col gap-y-1">
                    <Label className="text-xs text-muted-foreground">Bevestigd op</Label>
                    <div className="text-sm">
                        {user?.email_confirmed_at
                            ? new Date(user.email_confirmed_at).toLocaleString("nl-BE")
                            : "Nog niet bevestigd"}
                    </div>
                </div>
                <div className="flex flex-col gap-y-1">
                    <Label className="text-xs text-muted-foreground">Laatste login</Label>
                    <div className="text-sm">
                        {user?.last_sign_in_at
                            ? new Date(user.last_sign_in_at).toLocaleString("nl-BE")
                            : "—"}
                    </div>
                </div>
            </CardContent>
        </Card>
    );
}
