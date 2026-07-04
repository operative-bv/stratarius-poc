import { Input } from "@/components/ui/input"
import { SubmitButton } from "../ui/submit-button"
import { editTeamName } from "@/lib/actions/teams";
import { Label } from "../ui/label";
import { GetAccountResponse } from "@usebasejump/shared";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "../ui/card";

type Props = {
    account: GetAccountResponse;
}


export default function EditTeamName({ account }: Props) {

    return (
        <Card>
            <CardHeader>
                <CardTitle>Organisatie</CardTitle>
                <CardDescription>
                    Naam en identifier zijn uniek per organisatie
                </CardDescription>
            </CardHeader>
            <form className="animate-in flex-1 text-foreground">
                <input type="hidden" name="accountId" value={account.account_id} />
                <CardContent className="flex flex-col gap-y-6">
                    <div className="flex flex-col gap-y-2">
                        <Label htmlFor="name">
                            Naam organisatie
                        </Label>
                        <Input
                            defaultValue={account.name}
                            name="name"
                            placeholder="Mijn organisatie"
                            required
                        />
                    </div>
                </CardContent>
                <CardFooter>
                    <SubmitButton
                        formAction={editTeamName}
                        pendingText="Bijwerken..."
                    >
                        Opslaan
                    </SubmitButton>
                </CardFooter>
            </form>
        </Card>
    )
}
