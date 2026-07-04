import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { SubmitButton } from "@/components/ui/submit-button";
import { signOutOtherSessions } from "@/lib/actions/account-security";

export default function SessionsCard() {
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
            <form>
                <CardContent className="text-sm text-muted-foreground">
                    Deze actie invalideert refresh tokens op alle andere devices.
                    Je moet daar opnieuw inloggen om verder te gaan.
                </CardContent>
                <CardFooter>
                    <SubmitButton
                        formAction={signOutOtherSessions}
                        pendingText="Uitloggen..."
                        variant="outline"
                    >
                        Log uit op andere apparaten
                    </SubmitButton>
                </CardFooter>
            </form>
        </Card>
    );
}
