import SettingsNavigation from "@/components/dashboard/settings-navigation";
import DashboardTitle from "@/components/dashboard/dashboard-title";
import {Separator} from "@/components/ui/separator";

export default function TeamSettingsPage({children, params: {accountSlug}}: {children: React.ReactNode, params: {accountSlug: string}}) {
    const items = [
        { name: "Organisatie", href: `/dashboard/${accountSlug}/settings` },
        { name: "Leden", href: `/dashboard/${accountSlug}/settings/members` },
    ]
    return (
        <div className="hidden space-y-6 pb-16 md:block">
            <DashboardTitle title="Instellingen" description="Beheer organisatie-instellingen en leden." />
            <Separator />
            <div className="flex flex-col space-y-8 lg:flex-row lg:space-x-12 lg:space-y-0 w-full max-w-6xl mx-auto">
                <aside className="-mx-4 lg:w-1/5">
                    <SettingsNavigation items={items} />
                </aside>
                <div className="grow">{children}</div>
            </div>
        </div>
    )
}