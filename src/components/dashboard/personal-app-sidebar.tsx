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
import NavigatingAccountSelector from "@/components/dashboard/navigation-account-selector";

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
            <SidebarHeader className="border-b">
                <div className="flex items-center gap-2 px-2 py-1">
                    <div className="flex h-8 w-8 items-center justify-center rounded-md bg-primary text-primary-foreground text-sm font-bold">
                        S
                    </div>
                    <div className="flex flex-col group-data-[collapsible=icon]:hidden">
                        <span className="text-sm font-semibold tracking-tight">Stratarius</span>
                        <span className="text-xs text-muted-foreground">Persoonlijk account</span>
                    </div>
                </div>
                <div className="px-1 group-data-[collapsible=icon]:hidden">
                    <NavigatingAccountSelector accountId={accountId} />
                </div>
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

            <SidebarFooter className="border-t">
                <div className="p-2 group-data-[collapsible=icon]:hidden">
                    <UserAccountButton name={userName} email={userEmail} />
                </div>
            </SidebarFooter>
            <SidebarRail />
        </Sidebar>
    );
}
