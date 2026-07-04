import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/ui/submit-button";
import { changePassword } from "@/lib/actions/account-security";

export default function ChangePasswordCard() {
    return (
        <Card>
            <CardHeader>
                <CardTitle>Wachtwoord wijzigen</CardTitle>
                <CardDescription>
                    Kies een nieuw wachtwoord van minstens 8 tekens
                </CardDescription>
            </CardHeader>
            <form>
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
                    <SubmitButton formAction={changePassword} pendingText="Bijwerken...">
                        Wachtwoord wijzigen
                    </SubmitButton>
                </CardFooter>
            </form>
        </Card>
    );
}
