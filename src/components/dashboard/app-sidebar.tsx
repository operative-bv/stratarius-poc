"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarRail,
} from "@/components/ui/sidebar";
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
import UserAccountButton from "@/components/basejump/user-account-button";
import { TeamSwitcher } from "@/components/dashboard/team-switcher";
import { SidebarThemeToggle } from "@/components/theme-toggle";

type Item = { name: string; href: string; icon: React.ComponentType<{ className?: string }> };

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
    const pathname = usePathname();

    const analytics: Item[] = [
        { name: "Overview", href: `/dashboard/${accountSlug}`, icon: LayoutDashboard },
        { name: "Populatie", href: `/dashboard/${accountSlug}/populatie`, icon: Users },
        { name: "Loonkloof", href: `/dashboard/${accountSlug}/loonkloof`, icon: Scale },
    ];

    const modeling: Item[] = [
        { name: "Scenarios", href: `/dashboard/${accountSlug}/scenarios`, icon: FlaskConical },
        { name: "Simulator", href: `/dashboard/${accountSlug}/simulator`, icon: Sparkles },
    ];

    const data: Item[] = [
        { name: "Import", href: `/dashboard/${accountSlug}/import`, icon: Upload },
        { name: "Setup", href: `/dashboard/${accountSlug}/setup`, icon: Wrench },
    ];

    const settings: Item[] = [
        { name: "Organisatie", href: `/dashboard/${accountSlug}/settings`, icon: Settings },
        { name: "Leden", href: `/dashboard/${accountSlug}/settings/members`, icon: UsersRound },
    ];

    const isActive = (href: string) => {
        if (href === `/dashboard/${accountSlug}`) return pathname === href;
        return pathname === href || pathname.startsWith(`${href}/`);
    };

    const renderGroup = (label: string, items: Item[]) => (
        <SidebarGroup>
            <SidebarGroupLabel>{label}</SidebarGroupLabel>
            <SidebarGroupContent>
                <SidebarMenu>
                    {items.map((item) => (
                        <SidebarMenuItem key={item.href}>
                            <SidebarMenuButton asChild isActive={isActive(item.href)}>
                                <Link href={item.href}>
                                    <item.icon className="h-4 w-4" />
                                    <span>{item.name}</span>
                                </Link>
                            </SidebarMenuButton>
                        </SidebarMenuItem>
                    ))}
                </SidebarMenu>
            </SidebarGroupContent>
        </SidebarGroup>
    );

    return (
        <Sidebar collapsible="icon">
            <SidebarHeader>
                <TeamSwitcher activeAccountId={accountId} />
            </SidebarHeader>

            <SidebarContent>
                {renderGroup("Analyse", analytics)}
                {renderGroup("Modellering", modeling)}
                {renderGroup("Data", data)}
                {renderGroup("Settings", settings)}
            </SidebarContent>

            <SidebarFooter>
                <SidebarMenu>
                    <SidebarMenuItem>
                        <SidebarThemeToggle />
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                        <UserAccountButton name={userName} email={userEmail} />
                    </SidebarMenuItem>
                </SidebarMenu>
            </SidebarFooter>
            <SidebarRail />
        </Sidebar>
    );
}
