import {createClient} from "@/lib/supabase/server";
import DashboardHeader from "@/components/dashboard/dashboard-header";
import { ToastFromSearch } from "@/components/dashboard/toast-from-search";
import { redirect } from "next/navigation";
import { Suspense } from "react";

export default async function PersonalAccountDashboard({children, params: {accountSlug}}: {children: React.ReactNode, params: {accountSlug: string}}) {
    const supabaseClient = createClient();

    const {data: teamAccount, error} = await supabaseClient.rpc('get_account_by_slug', {
        slug: accountSlug
    });

    if (!teamAccount) {
        redirect('/dashboard');
    }

    const navigation = [
        {
            name: 'Overview',
            href: `/dashboard/${accountSlug}`,
        },
        {
            name: 'Populatie',
            href: `/dashboard/${accountSlug}/populatie`
        },
        {
            name: 'Scenarios',
            href: `/dashboard/${accountSlug}/scenarios`
        },
        {
            name: 'Loonkloof',
            href: `/dashboard/${accountSlug}/loonkloof`
        },
        {
            name: 'Import',
            href: `/dashboard/${accountSlug}/import`
        },
        {
            name: 'Simulator',
            href: `/dashboard/${accountSlug}/simulator`
        },
        {
            name: 'Settings',
            href: `/dashboard/${accountSlug}/settings`
        }
    ]

    return (
        <>
            <DashboardHeader accountId={teamAccount.account_id} navigation={navigation}/>
            <Suspense fallback={null}><ToastFromSearch /></Suspense>
            <div className="w-full p-8">{children}</div>
        </>
    )

}