"use client";

import { Home, User, Users } from "lucide-react";
import SidebarShell, { type SidebarNavGroup } from "@/components/dashboard/sidebar-shell";

export default function PersonalAppSidebar({
    accountId,
    userName,
    userEmail,
}: {
    accountId: string;
    userName?: string;
    userEmail?: string;
}) {
    const groups: SidebarNavGroup[] = [
        {
            label: "Account",
            items: [
                { name: "Overview", href: "/dashboard", icon: Home },
                { name: "Profiel", href: "/dashboard/settings", icon: User },
                { name: "Organisaties", href: "/dashboard/settings/teams", icon: Users },
            ],
        },
    ];

    return (
        <SidebarShell
            accountId={accountId}
            userName={userName}
            userEmail={userEmail}
            groups={groups}
            homeHref="/dashboard"
        />
    );
}
