import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import AppSidebar from "@/components/dashboard/app-sidebar";
import SiteHeader from "@/components/dashboard/site-header";
import { ToastFromSearch } from "@/components/dashboard/toast-from-search";

export default async function PersonalAccountDashboard({
    children,
    params: { accountSlug },
}: {
    children: React.ReactNode;
    params: { accountSlug: string };
}) {
    const supabaseClient = createClient();

    const { data: teamAccount } = await supabaseClient.rpc("get_account_by_slug", { slug: accountSlug });

    if (!teamAccount) {
        redirect("/dashboard");
    }

    const { data: personalAccount } = await supabaseClient.rpc("get_personal_account");

    return (
        <SidebarProvider>
            <AppSidebar
                accountSlug={accountSlug}
                accountId={teamAccount.account_id}
                userName={personalAccount?.name}
                userEmail={personalAccount?.email}
            />
            <SidebarInset>
                <SiteHeader accountSlug={accountSlug} accountName={teamAccount.name} />
                <Suspense fallback={null}>
                    <ToastFromSearch />
                </Suspense>
                <main className="flex flex-1 flex-col gap-4 p-4 md:gap-6 md:p-6">{children}</main>
            </SidebarInset>
        </SidebarProvider>
    );
}
