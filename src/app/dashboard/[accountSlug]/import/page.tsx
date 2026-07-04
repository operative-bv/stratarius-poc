import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Upload, Link2 } from "lucide-react";
import ImportForm from "@/components/import/import-form";

export default async function ImportPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();
    const { count } = await supabase.from("dim_contract").select("contract_id", { count: "exact", head: true });
    const totalContracts = count ?? 0;

    return (
        <div className="mx-auto max-w-5xl py-8 space-y-6">
            <div>
                <h1 className="text-3xl font-bold flex items-center gap-2">
                    <Upload className="h-7 w-7" />
                    Data import
                </h1>
                <p className="text-muted-foreground text-sm mt-1">
                    Bulk-import contracten + baseline lonen. Momenteel {totalContracts} contracten in populatie.
                </p>
            </div>

            <div className="grid gap-6 md:grid-cols-2">
                <ImportForm accountSlug={accountSlug} />

                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Link2 className="h-5 w-5" />
                            HR-systeem koppelingen
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <p className="text-sm text-muted-foreground mb-4">
                            Directe integraties met payroll- en HR-suites voor continue sync. Roadmap Q3-Q4 2026.
                        </p>

                        <div className="space-y-3">
                            <ConnectorCard name="Workday HCM" desc="Employees API + compensation module" status="Q3 2026" />
                            <ConnectorCard name="BambooHR" desc="Employees + custom fields + org chart" status="Q3 2026" />
                            <ConnectorCard name="SD Worx eBlox" desc="Belgische payroll — directe RSZ-integratie" status="Q4 2026" />
                            <ConnectorCard name="Attentia" desc="Belgische HR + wagen fleet management" status="Q4 2026" />
                        </div>

                        <p className="text-xs text-muted-foreground mt-4">
                            Elk connector-type mapt HR-velden naar Stratarius schema (dim_persoon, dim_contract, fact_looncomponent). Rechtsgrondslag wordt gelogd per sync via <code>gdpr_access_log</code>.
                        </p>
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}

function ConnectorCard({ name, desc, status }: { name: string; desc: string; status: string }) {
    return (
        <div className="flex items-center justify-between border rounded-lg p-3">
            <div>
                <div className="text-sm font-medium">{name}</div>
                <div className="text-xs text-muted-foreground">{desc}</div>
            </div>
            <Badge variant="outline">{status}</Badge>
        </div>
    );
}
