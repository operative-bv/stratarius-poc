"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Building2, ChevronsUpDown, Plus, User } from "lucide-react";

import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuShortcut,
    DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from "@/components/ui/dialog";
import {
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    useSidebar,
} from "@/components/ui/sidebar";
import { useAccounts } from "@/lib/hooks/use-accounts";
import NewTeamForm from "@/components/basejump/new-team-form";

export function TeamSwitcher({ activeAccountId }: { activeAccountId: string }) {
    const { isMobile } = useSidebar();
    const router = useRouter();
    const [showNewTeamDialog, setShowNewTeamDialog] = React.useState(false);

    const { data: accounts } = useAccounts();
    const activeAccount = accounts?.find((a) => a.account_id === activeAccountId);
    const teamAccounts = accounts?.filter((a) => !a.personal_account) ?? [];
    const personalAccount = accounts?.find((a) => a.personal_account);

    if (!activeAccount) {
        return null;
    }

    const isPersonal = activeAccount.personal_account;
    const ActiveLogo = isPersonal ? User : Building2;
    const plan = isPersonal ? "Persoonlijk" : "Organisatie";

    const goToAccount = (slug: string | null, personal: boolean) => {
        if (personal) router.push("/dashboard");
        else if (slug) router.push(`/dashboard/${slug}`);
    };

    return (
        <Dialog open={showNewTeamDialog} onOpenChange={setShowNewTeamDialog}>
            <SidebarMenu>
                <SidebarMenuItem>
                    <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                            <SidebarMenuButton
                                size="lg"
                                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                            >
                                <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
                                    <ActiveLogo className="size-4" />
                                </div>
                                <div className="grid flex-1 text-left text-sm leading-tight">
                                    <span className="truncate font-semibold">{activeAccount.name}</span>
                                    <span className="truncate text-xs">{plan}</span>
                                </div>
                                <ChevronsUpDown className="ml-auto" />
                            </SidebarMenuButton>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent
                            className="w-[--radix-dropdown-menu-trigger-width] min-w-56 rounded-lg"
                            align="start"
                            side={isMobile ? "bottom" : "right"}
                            sideOffset={4}
                        >
                            {personalAccount && (
                                <>
                                    <DropdownMenuLabel className="text-xs text-muted-foreground">
                                        Persoonlijk
                                    </DropdownMenuLabel>
                                    <DropdownMenuItem
                                        onClick={() => goToAccount(null, true)}
                                        className="gap-2 p-2"
                                    >
                                        <div className="flex size-6 items-center justify-center rounded-sm border">
                                            <User className="size-4 shrink-0" />
                                        </div>
                                        {personalAccount.name}
                                    </DropdownMenuItem>
                                </>
                            )}

                            {teamAccounts.length > 0 && (
                                <>
                                    <DropdownMenuLabel className="text-xs text-muted-foreground">
                                        Organisaties
                                    </DropdownMenuLabel>
                                    {teamAccounts.map((team, index) => (
                                        <DropdownMenuItem
                                            key={team.account_id}
                                            onClick={() => goToAccount(team.slug, false)}
                                            className="gap-2 p-2"
                                        >
                                            <div className="flex size-6 items-center justify-center rounded-sm border">
                                                <Building2 className="size-4 shrink-0" />
                                            </div>
                                            {team.name}
                                            <DropdownMenuShortcut>⌘{index + 1}</DropdownMenuShortcut>
                                        </DropdownMenuItem>
                                    ))}
                                </>
                            )}

                            <DropdownMenuSeparator />
                            <DialogTrigger asChild>
                                <DropdownMenuItem
                                    onSelect={(e) => {
                                        e.preventDefault();
                                        setShowNewTeamDialog(true);
                                    }}
                                    className="gap-2 p-2"
                                >
                                    <div className="flex size-6 items-center justify-center rounded-md border bg-background">
                                        <Plus className="size-4" />
                                    </div>
                                    <div className="font-medium text-muted-foreground">Nieuwe organisatie</div>
                                </DropdownMenuItem>
                            </DialogTrigger>
                        </DropdownMenuContent>
                    </DropdownMenu>
                </SidebarMenuItem>
            </SidebarMenu>

            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Nieuwe organisatie aanmaken</DialogTitle>
                    <DialogDescription>
                        Een organisatie is een aparte klant-entiteit met eigen medewerkers en data.
                    </DialogDescription>
                </DialogHeader>
                <NewTeamForm />
            </DialogContent>
        </Dialog>
    );
}
