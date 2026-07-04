"use client";

import { useFormState, useFormStatus } from "react-dom";
import { useEffect } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { RefreshCw, Loader2 } from "lucide-react";
import { initialRefreshMartState, refreshMartAction } from "@/lib/actions/refresh-mart-action";

function Btn() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" variant="outline" size="sm" disabled={pending}>
            {pending ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <RefreshCw className="h-4 w-4 mr-2" />}
            {pending ? "Bezig..." : "Refresh mart"}
        </Button>
    );
}

export default function RefreshMartButton({ accountSlug }: { accountSlug: string }) {
    const bound = refreshMartAction.bind(null, accountSlug);
    const [state, formAction] = useFormState(bound, initialRefreshMartState);

    useEffect(() => {
        if (state.ok === true && state.message) toast.success(state.message);
        if (state.ok === false && state.message) toast.error(state.message);
    }, [state]);

    return (
        <form action={formAction}>
            <Btn />
        </form>
    );
}
