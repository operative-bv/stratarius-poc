"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Separator } from "@/components/ui/separator";
import {
    Breadcrumb,
    BreadcrumbItem,
    BreadcrumbLink,
    BreadcrumbList,
    BreadcrumbPage,
    BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";

const LABELS: Record<string, string> = {
    dashboard: "Dashboard",
    populatie: "Populatie",
    loonkloof: "Loonkloof",
    scenarios: "Scenarios",
    simulator: "Simulator",
    import: "Import",
    setup: "Setup",
    settings: "Settings",
    teams: "Organisaties",
    billing: "Billing",
};

export default function SiteHeader({
    mode = "team",
    accountSlug,
    accountName,
}: {
    mode?: "team" | "personal";
    accountSlug?: string;
    accountName?: string;
}) {
    const pathname = usePathname();
    const segments = pathname.split("/").filter(Boolean);
    // team: ["dashboard", "<slug>", "<page>", ...]
    // personal: ["dashboard", "<page>", ...]
    const pageSegment = mode === "team" ? segments[2] : segments[1];
    const subSegment = mode === "team" ? segments[3] : segments[2];
    const rootHref = mode === "team" ? `/dashboard/${accountSlug}` : "/dashboard";
    const rootLabel = mode === "team" ? accountName ?? "Dashboard" : "Persoonlijk";

    return (
        <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b bg-background/95 backdrop-blur px-4">
            <SidebarTrigger className="-ml-1" />
            <Separator orientation="vertical" className="mr-2 h-4" />
            <Breadcrumb>
                <BreadcrumbList>
                    <BreadcrumbItem className="hidden sm:block">
                        <BreadcrumbLink asChild>
                            <Link href={rootHref}>{rootLabel}</Link>
                        </BreadcrumbLink>
                    </BreadcrumbItem>
                    {pageSegment && (
                        <>
                            <BreadcrumbSeparator className="hidden sm:block" />
                            <BreadcrumbItem>
                                {subSegment ? (
                                    <BreadcrumbLink asChild>
                                        <Link href={`${rootHref}/${pageSegment}`}>
                                            {LABELS[pageSegment] ?? pageSegment}
                                        </Link>
                                    </BreadcrumbLink>
                                ) : (
                                    <BreadcrumbPage>{LABELS[pageSegment] ?? pageSegment}</BreadcrumbPage>
                                )}
                            </BreadcrumbItem>
                        </>
                    )}
                    {subSegment && (
                        <>
                            <BreadcrumbSeparator className="hidden sm:block" />
                            <BreadcrumbItem>
                                <BreadcrumbPage>{LABELS[subSegment] ?? subSegment}</BreadcrumbPage>
                            </BreadcrumbItem>
                        </>
                    )}
                    {!pageSegment && (
                        <BreadcrumbItem className="sm:hidden">
                            <BreadcrumbPage>Overview</BreadcrumbPage>
                        </BreadcrumbItem>
                    )}
                </BreadcrumbList>
            </Breadcrumb>
        </header>
    );
}
