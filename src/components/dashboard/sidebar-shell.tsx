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
import UserAccountButton from "@/components/basejump/user-account-button";
import { TeamSwitcher } from "@/components/dashboard/team-switcher";
import { SidebarThemeToggle } from "@/components/theme-toggle";

export type SidebarNavItem = {
    name: string;
    href: string;
    icon: React.ComponentType<{ className?: string }>;
};

export type SidebarNavGroup = {
    label: string;
    items: SidebarNavItem[];
};

/**
 * Shared shell voor AppSidebar (team) en PersonalAppSidebar. Rendert
 * het canonieke shadcn sidebar-07 pattern: TeamSwitcher in de header,
 * nav groups in de content, ThemeToggle + UserAccountButton in de footer.
 *
 * Home-route bepaalt of Overview matcht op exact-equal (bijv. `/dashboard/foo`)
 * of op prefix (rest van de items via startsWith).
 */
export default function SidebarShell({
    accountId,
    userName,
    userEmail,
    groups,
    homeHref,
}: {
    accountId: string;
    userName?: string;
    userEmail?: string;
    groups: SidebarNavGroup[];
    homeHref: string;
}) {
    const pathname = usePathname();

    const isActive = (href: string) => {
        if (href === homeHref) return pathname === href;
        return pathname === href || pathname.startsWith(`${href}/`);
    };

    return (
        <Sidebar collapsible="icon">
            <SidebarHeader>
                <TeamSwitcher activeAccountId={accountId} />
            </SidebarHeader>

            <SidebarContent>
                {groups.map((group) => (
                    <SidebarGroup key={group.label}>
                        <SidebarGroupLabel>{group.label}</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                {group.items.map((item) => (
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
                ))}
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
