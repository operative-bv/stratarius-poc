"use client";

import { useEffect } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { toast } from "sonner";

/**
 * Leest ?toast_success=... of ?toast_error=... uit de URL, toont een Sonner
 * toast en verwijdert daarna de query-param zodat refresh geen dubbele toast geeft.
 *
 * Server actions die feedback willen geven doen:
 *   redirect(`/foo?toast_success=Scenario aangemaakt`)
 */
export function ToastFromSearch() {
    const searchParams = useSearchParams();
    const router = useRouter();
    const pathname = usePathname();

    useEffect(() => {
        const success = searchParams.get("toast_success");
        const error = searchParams.get("toast_error");
        if (!success && !error) return;

        if (success) toast.success(success);
        if (error) toast.error(error);

        const params = new URLSearchParams(searchParams);
        params.delete("toast_success");
        params.delete("toast_error");
        const qs = params.toString();
        router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    }, [searchParams, router, pathname]);

    return null;
}
