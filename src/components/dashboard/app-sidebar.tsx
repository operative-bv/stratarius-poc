import {
    LayoutDashboard,
    Users,
    UsersRound,
    FlaskConical,
    Scale,
    Upload,
    Wrench,
    Settings,
    Sparkles,
} from "lucide-react";
import SidebarShell, { type SidebarNavGroup } from "@/components/dashboard/sidebar-shell";

export default function AppSidebar({
    accountSlug,
    accountId,
    userName,
    userEmail,
}: {
    accountSlug: string;
    accountId: string;
    userName?: string;
    userEmail?: string;
}) {
    const homeHref = `/dashboard/${accountSlug}`;

    const groups: SidebarNavGroup[] = [
        {
            label: "Analyse",
            items: [
                { name: "Overview", href: homeHref, icon: LayoutDashboard },
                { name: "Populatie", href: `${homeHref}/populatie`, icon: Users },
                { name: "Loonkloof", href: `${homeHref}/loonkloof`, icon: Scale },
            ],
        },
        {
            label: "Modellering",
            items: [
                { name: "Scenarios", href: `${homeHref}/scenarios`, icon: FlaskConical },
                { name: "Simulator", href: `${homeHref}/simulator`, icon: Sparkles },
            ],
        },
        {
            label: "Data",
            items: [
                { name: "Import", href: `${homeHref}/import`, icon: Upload },
                { name: "Setup", href: `${homeHref}/setup`, icon: Wrench },
            ],
        },
        {
            label: "Settings",
            items: [
                { name: "Organisatie", href: `${homeHref}/settings`, icon: Settings },
                { name: "Leden", href: `${homeHref}/settings/members`, icon: UsersRound },
            ],
        },
    ];

    return (
        <SidebarShell
            accountId={accountId}
            userName={userName}
            userEmail={userEmail}
            groups={groups}
            homeHref={homeHref}
        />
    );
}
