import { createClient } from "@/lib/supabase/server";
import ManageTeamMembers from "@/components/basejump/manage-team-members";
import ManageTeamInvitations from "@/components/basejump/manage-team-invitations";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { PageHeader } from "@/components/dashboard/page-header";
import { UsersRound } from "lucide-react";

export default async function TeamMembersPage({ params: { accountSlug } }: { params: { accountSlug: string } }) {
    const supabaseClient = createClient();
    const { data: teamAccount } = await supabaseClient.rpc("get_account_by_slug", { slug: accountSlug });

    if (teamAccount.account_role !== "owner") {
        return (
            <>
                <PageHeader
                    icon={UsersRound}
                    title="Leden"
                    description="Beheer teamleden en uitnodigingen"
                />
                <Alert variant="destructive">
                    <AlertDescription>Je hebt geen toegang tot deze pagina — alleen owners kunnen leden beheren.</AlertDescription>
                </Alert>
            </>
        );
    }

    return (
        <>
            <PageHeader
                icon={UsersRound}
                title="Leden"
                description="Beheer teamleden en uitnodigingen"
            />
            <div className="flex flex-col gap-y-4">
                <ManageTeamInvitations accountId={teamAccount.account_id} />
                <ManageTeamMembers accountId={teamAccount.account_id} />
            </div>
        </>
    );
}
