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

    return (
        <SidebarProvider>
            <AppSidebar accountSlug={accountSlug} accountId={teamAccount.account_id} />
            <SidebarInset>
                <SiteHeader accountSlug={accountSlug} accountName={teamAccount.name} />
                <Suspense fallback={null}>
                    <ToastFromSearch />
                </Suspense>
                <main className="flex-1 p-6 md:p-8">{children}</main>
            </SidebarInset>
        </SidebarProvider>
    );
}
