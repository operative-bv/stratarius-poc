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
};

export default function SiteHeader({ accountSlug, accountName }: { accountSlug: string; accountName?: string }) {
    const pathname = usePathname();
    const segments = pathname.split("/").filter(Boolean);
    // segments = ["dashboard", "<slug>", "<page>", ...]
    const currentPage = segments[2] ? LABELS[segments[2]] ?? segments[2] : "Overview";

    return (
        <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b bg-background/95 backdrop-blur px-4">
            <SidebarTrigger className="-ml-1" />
            <Separator orientation="vertical" className="mr-2 h-4" />
            <Breadcrumb>
                <BreadcrumbList>
                    <BreadcrumbItem className="hidden sm:block">
                        <BreadcrumbLink asChild>
                            <Link href={`/dashboard/${accountSlug}`}>{accountName ?? "Dashboard"}</Link>
                        </BreadcrumbLink>
                    </BreadcrumbItem>
                    {segments[2] && (
                        <>
                            <BreadcrumbSeparator className="hidden sm:block" />
                            <BreadcrumbItem>
                                <BreadcrumbPage>{currentPage}</BreadcrumbPage>
                            </BreadcrumbItem>
                        </>
                    )}
                    {!segments[2] && (
                        <BreadcrumbItem className="sm:hidden">
                            <BreadcrumbPage>Overview</BreadcrumbPage>
                        </BreadcrumbItem>
                    )}
                </BreadcrumbList>
            </Breadcrumb>
        </header>
    );
}
