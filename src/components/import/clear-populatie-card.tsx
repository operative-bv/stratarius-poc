"use client";

import { useEffect } from "react";
import { useFormState, useFormStatus } from "react-dom";
import { toast } from "sonner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
    AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Trash2, Loader2, AlertTriangle } from "lucide-react";
import { clearPopulatieAction } from "@/lib/actions/clear-populatie-action";
import { initialClearPopulatieState } from "@/lib/actions/clear-populatie-types";

function ConfirmBtn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" variant="destructive" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Trash2 className="h-4 w-4 mr-2" />}
            {pending ? "Bezig met wissen..." : "Ja, wis populatie"}
        </Button>
    );
}

export default function ClearPopulatieCard({
    accountSlug,
    totalContracts,
}: {
    accountSlug: string;
    totalContracts: number;
}) {
    const bound = clearPopulatieAction.bind(null, accountSlug);
    const [state, formAction] = useFormState(bound, initialClearPopulatieState);

    useEffect(() => {
        if (state.ok === true) {
            toast.success(
                `Populatie gewist — ${state.deletedContracten} contract${state.deletedContracten === 1 ? "" : "en"} en ${state.deletedPersonen} persoon${state.deletedPersonen === 1 ? "" : "en"} verwijderd`,
            );
        }
        if (state.ok === false && state.message) {
            toast.error(state.message);
        }
    }, [state]);

    if (totalContracts === 0) {
        return null;
    }

    return (
        <Card className="border-destructive/40">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-base">
                    <AlertTriangle className="h-4 w-4 text-destructive" />
                    Populatie leegmaken
                </CardTitle>
                <CardDescription>
                    Er staan al <span className="font-medium text-foreground">{totalContracts}</span>{" "}
                    contracten in je populatie. Nieuwe imports worden erbij opgeteld (geen dedup) — elke import
                    maakt nieuwe personen aan ook al is de naam gelijk.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <AlertDialog>
                    <AlertDialogTrigger asChild>
                        <Button variant="outline" size="sm">
                            <Trash2 className="h-4 w-4 mr-2" />
                            Wis populatie…
                        </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                        <AlertDialogHeader>
                            <AlertDialogTitle>Populatie wissen?</AlertDialogTitle>
                            <AlertDialogDescription>
                                Dit verwijdert alle <span className="font-medium text-foreground">{totalContracts}</span>{" "}
                                contracten, hun personen, loon-componenten en cascade-uitkomsten voor deze
                                organisatie. Dim_functie (teams), scenarios en organisatie-config blijven staan.
                                <br />
                                <br />
                                Dit kan niet ongedaan gemaakt worden.
                            </AlertDialogDescription>
                        </AlertDialogHeader>
                        <form action={formAction}>
                            <AlertDialogFooter>
                                <AlertDialogCancel>Annuleer</AlertDialogCancel>
                                <AlertDialogAction asChild>
                                    <ConfirmBtn />
                                </AlertDialogAction>
                            </AlertDialogFooter>
                        </form>
                    </AlertDialogContent>
                </AlertDialog>
            </CardContent>
        </Card>
    );
}
