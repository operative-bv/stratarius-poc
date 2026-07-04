import EditPersonalAccountName from "@/components/basejump/edit-personal-account-name";
import AccountInfoCard from "@/components/account/account-info-card";
import ChangePasswordCard from "@/components/account/change-password-card";
import SessionsCard from "@/components/account/sessions-card";
import { createClient } from "@/lib/supabase/server";

export default async function PersonalAccountSettingsPage() {
    const supabaseClient = createClient();
    const { data: personalAccount } = await supabaseClient.rpc("get_personal_account");

    return (
        <div className="flex flex-col gap-y-6">
            <EditPersonalAccountName account={personalAccount} />
            <AccountInfoCard />
            <ChangePasswordCard />
            <SessionsCard />
        </div>
    );
}
