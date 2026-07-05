import { createClient } from "@/lib/supabase/server";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import PersonalAppSidebar from "@/components/dashboard/personal-app-sidebar";
import SiteHeader from "@/components/dashboard/site-header";
import { Suspense } from "react";
import { ToastFromSearch } from "@/components/dashboard/toast-from-search";

export default async function PersonalAccountDashboard({
    children,
}: {
    children: React.ReactNode;
}) {
    const supabaseClient = createClient();
    const { data: personalAccount } = await supabaseClient.rpc("get_personal_account");

    return (
        <SidebarProvider>
            <PersonalAppSidebar
                accountId={personalAccount.account_id}
                userName={personalAccount?.name}
                userEmail={personalAccount?.email}
            />
            <SidebarInset>
                <SiteHeader mode="personal" />
                <Suspense fallback={null}>
                    <ToastFromSearch />
                </Suspense>
                <main className="flex flex-1 flex-col gap-4 p-4 md:gap-6 md:p-6">{children}</main>
            </SidebarInset>
        </SidebarProvider>
    );
}
