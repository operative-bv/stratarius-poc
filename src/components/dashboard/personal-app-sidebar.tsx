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
import { Home, User, Users } from "lucide-react";
import UserAccountButton from "@/components/basejump/user-account-button";
import { TeamSwitcher } from "@/components/dashboard/team-switcher";
import { SidebarThemeToggle } from "@/components/theme-toggle";

type Item = { name: string; href: string; icon: React.ComponentType<{ className?: string }> };

export default function PersonalAppSidebar({
    accountId,
    userName,
    userEmail,
}: {
    accountId: string;
    userName?: string;
    userEmail?: string;
}) {
    const pathname = usePathname();

    const nav: Item[] = [
        { name: "Overview", href: "/dashboard", icon: Home },
        { name: "Profiel", href: "/dashboard/settings", icon: User },
        { name: "Organisaties", href: "/dashboard/settings/teams", icon: Users },
    ];

    const isActive = (href: string) => {
        if (href === "/dashboard") return pathname === "/dashboard";
        return pathname === href || pathname.startsWith(`${href}/`);
    };

    return (
        <Sidebar collapsible="icon">
            <SidebarHeader>
                <TeamSwitcher activeAccountId={accountId} />
            </SidebarHeader>

            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupLabel>Account</SidebarGroupLabel>
                    <SidebarGroupContent>
                        <SidebarMenu>
                            {nav.map((item) => (
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
