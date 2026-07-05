import ManageTeams from "@/components/basejump/manage-teams";
import { PageHeader } from "@/components/dashboard/page-header";
import { Users } from "lucide-react";

export default async function PersonalAccountTeamsPage() {
    return (
        <>
            <PageHeader
                icon={Users}
                title="Organisaties"
                description="Bekijk je bestaande teams en maak nieuwe organisaties aan"
            />
            <ManageTeams />
        </>
    );
}
