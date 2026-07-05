import EditTeamName from "@/components/basejump/edit-team-name";
import EditTeamSlug from "@/components/basejump/edit-team-slug";
import { PageHeader } from "@/components/dashboard/page-header";
import { createClient } from "@/lib/supabase/server";
import { Settings } from "lucide-react";

export default async function TeamSettingsPage({ params: { accountSlug } }: { params: { accountSlug: string } }) {
    const supabaseClient = createClient();
    const { data: teamAccount } = await supabaseClient.rpc("get_account_by_slug", { slug: accountSlug });

    return (
        <>
            <PageHeader
                icon={Settings}
                title="Organisatie"
                description="Naam en URL slug van deze organisatie"
            />
            <div className="flex flex-col gap-y-4">
                <EditTeamName account={teamAccount} />
                <EditTeamSlug account={teamAccount} />
            </div>
        </>
    );
}
