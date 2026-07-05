import EditPersonalAccountName from "@/components/basejump/edit-personal-account-name";
import AccountInfoCard from "@/components/account/account-info-card";
import ChangePasswordCard from "@/components/account/change-password-card";
import SessionsCard from "@/components/account/sessions-card";
import { PageHeader } from "@/components/dashboard/page-header";
import { createClient } from "@/lib/supabase/server";
import { User } from "lucide-react";

export default async function PersonalAccountSettingsPage() {
    const supabaseClient = createClient();
    const { data: personalAccount } = await supabaseClient.rpc("get_personal_account");

    return (
        <>
            <PageHeader
                icon={User}
                title="Profiel"
                description="Beheer je persoonlijke inloggegevens en actieve sessies"
            />
            <div className="flex flex-col gap-y-4">
                <EditPersonalAccountName account={personalAccount} />
                <AccountInfoCard />
                <ChangePasswordCard />
                <SessionsCard />
            </div>
        </>
    );
}
