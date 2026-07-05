import { createClient } from "@/lib/supabase/server";
import { roundFinal as roundFinalMirror } from "@/lib/cascade-mirror";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
    Users,
    Euro,
    TrendingUp,
    TrendingDown,
    BarChart3,
    ArrowRight,
    Briefcase,
    Wrench,
    GraduationCap,
    Crown,
    Sparkles,
} from "lucide-react";
import Link from "next/link";
import { redirect } from "next/navigation";
import LoonkostChart from "@/components/dashboard/loonkost-chart";

type PopRow = {
    contract_id: string;
    functienaam: string;
    status: string;
    bruto: number;
    totaal_patronale_kost: number;
    tco: number;
};

const roundFinal = (value: number): string => roundFinalMirror(value, { digits: 0 });

const TEAM_ICONS: Record<string, typeof Users> = {
    Sales: Briefcase,
    Engineering: Wrench,
    Operations: GraduationCap,
    Management: Crown,
};

// POC helper: bouw 12-maands series uit huidige snapshot met lichte seasonaliteit.
// Piekmaanden voor vakantiegeld (mei/juni) en eindejaarspremie (december) worden
// (nog) niet echt gemodelleerd — visualisatie is representatief, geen echte historie.
function buildMonthlySeries(bruto: number, patronaal: number) {
    const maanden = ["Jan", "Feb", "Mrt", "Apr", "Mei", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"];
    // Groeicurve met kleine piek in mei (vakantiegeld) en dec (eindejaarspremie)
    const seasonality = [0.98, 0.98, 0.99, 1.0, 1.02, 1.03, 1.02, 1.01, 1.0, 1.01, 1.02, 1.05];
    return maanden.map((m, i) => ({
        maand: m,
        bruto: Math.round(bruto * seasonality[i]),
        patronaal: Math.round(patronaal * seasonality[i]),
    }));
}

export default async function TeamDashboardPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    if (accountData?.account_id) {
        const { data: entiteitData } = await supabase
            .from("dim_legale_entiteit")
            .select("legale_entiteit_id")
            .eq("owning_account_id", accountData.account_id)
            .limit(1);
        if (!entiteitData || entiteitData.length === 0) {
            redirect(`/dashboard/${accountSlug}/setup`);
        }
    }

    // ISS-080: expliciete error propagation — anders toont dashboard "0 headcount"
    // bij RPC failures wat identiek is aan een echte lege populatie.
    const { data: scenariosData, error: scenErr } = await supabase
        .from("dim_scenario")
        .select("scenario_id, naam, kind")
        .eq("kind", "baseline")
        .limit(1);
    const baselineId = scenariosData?.[0]?.scenario_id ?? null;

    const { data, error: cascadeErr } = await supabase.rpc("cascade_populatie_snapshot", {
        p_periode: "2024-06-01",
        p_scenario_id: baselineId,
    });
    const loadError = scenErr?.message ?? cascadeErr?.message ?? null;
    const rows = (data ?? []) as PopRow[];

    const headcount = rows.length;
    const totalBruto = rows.reduce((s, r) => s + Number(r.bruto), 0);
    const totalPatronale = rows.reduce((s, r) => s + Number(r.totaal_patronale_kost), 0);
    const totalTco = rows.reduce((s, r) => s + Number(r.tco), 0);
    const patronalePct = totalBruto > 0 ? (totalPatronale / totalBruto) * 100 : 0;
    const gemBruto = headcount > 0 ? totalBruto / headcount : 0;

    const teams = new Map<string, { count: number; bruto: number; tco: number }>();
    for (const r of rows) {
        const cur = teams.get(r.functienaam) ?? { count: 0, bruto: 0, tco: 0 };
        teams.set(r.functienaam, {
            count: cur.count + 1,
            bruto: cur.bruto + Number(r.bruto),
            tco: cur.tco + Number(r.tco),
        });
    }
    const teamRows = Array.from(teams.entries()).sort((a, b) => b[1].tco - a[1].tco);

    const chartData = buildMonthlySeries(totalBruto, totalPatronale);

    return (
        <div className="space-y-6">
            {/* Page header */}
            <div className="flex flex-col gap-2">
                <h1 className="text-2xl font-semibold tracking-tight">Werkgeverskost overzicht</h1>
                <p className="text-sm text-muted-foreground">
                    Baseline scenario · periode juni 2024 · {headcount} medewerkers · demo dataset
                </p>
            </div>

            {loadError && (
                <Card className="border-destructive/40">
                    <CardContent className="pt-6">
                        <p className="text-sm text-destructive">Data laden faalde: {loadError}</p>
                    </CardContent>
                </Card>
            )}

            {/* KPI Section cards — dashboard-01 style */}
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
                <SectionCard
                    label="Headcount"
                    value={headcount.toString()}
                    icon={Users}
                    trend={{ direction: "up", pct: "+3", note: "vs vorige maand" }}
                    footer={`Gemiddeld bruto € ${roundFinal(gemBruto)} / persoon`}
                />
                <SectionCard
                    label="Bruto loonsom (maand)"
                    value={`€ ${roundFinal(totalBruto)}`}
                    icon={Euro}
                    trend={{ direction: "up", pct: "+2.1%", note: "vs vorige periode" }}
                    footer="Som van fact_looncomponent basisloon"
                />
                <SectionCard
                    label="Patronale kost"
                    value={`€ ${roundFinal(totalPatronale)}`}
                    icon={BarChart3}
                    trend={{
                        direction: patronalePct > 30 ? "up" : "down",
                        pct: `${patronalePct.toFixed(1)}%`,
                        note: "van bruto loonsom",
                    }}
                    footer="Cascade stap 2-9 (RSZ + vermindering + vakantiegeld + wagen + arbeidsongevallen)"
                />
                <SectionCard
                    label="Totale werkgeverskost"
                    value={`€ ${roundFinal(totalTco)}`}
                    icon={TrendingUp}
                    trend={{ direction: "up", pct: "TCO", note: "bruto + patronaal" }}
                    footer={`Jaarbasis: € ${roundFinal(totalTco * 12)}`}
                    highlight
                />
            </div>

            {/* Chart + Team panel */}
            <div className="grid gap-4 lg:grid-cols-3">
                <Card className="lg:col-span-2">
                    <CardHeader>
                        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                            <div>
                                <CardTitle>Loonkost trend 2024</CardTitle>
                                <p className="text-xs text-muted-foreground mt-1">
                                    Bruto + patronaal gestapeld · pieken tonen seizoenspatroon (vakantiegeld · eindejaarspremie)
                                </p>
                            </div>
                            <Badge variant="outline" className="w-fit gap-1 text-xs">
                                <Sparkles className="h-3 w-3" />
                                Representatief · POC
                            </Badge>
                        </div>
                    </CardHeader>
                    <CardContent className="pl-2">
                        <LoonkostChart data={chartData} />
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Users className="h-5 w-5" />
                            TCO per team
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <div className="space-y-3">
                            {teamRows.map(([name, stats]) => {
                                const Icon = TEAM_ICONS[name] ?? Users;
                                const pct = totalTco > 0 ? (stats.tco / totalTco) * 100 : 0;
                                return (
                                    <div key={name} className="space-y-2">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center gap-2">
                                                <Icon className="h-4 w-4 text-muted-foreground" />
                                                <span className="text-sm font-medium">{name}</span>
                                            </div>
                                            <div className="text-right">
                                                <div className="text-sm font-semibold tabular-nums">€ {roundFinal(stats.tco)}</div>
                                                <div className="text-xs text-muted-foreground">{stats.count} × · {pct.toFixed(0)}%</div>
                                            </div>
                                        </div>
                                        <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                                            <div
                                                className="h-full bg-primary rounded-full transition-all"
                                                style={{ width: `${pct}%` }}
                                            />
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    </CardContent>
                </Card>
            </div>

            {/* Quick actions */}
            <Card>
                <CardHeader>
                    <CardTitle>Snel naar</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="grid gap-3 md:grid-cols-3">
                        <QuickLink
                            href={`/dashboard/${accountSlug}/populatie`}
                            title="Populatie snapshot"
                            desc="Alle contracten met filters"
                        />
                        <QuickLink
                            href={`/dashboard/${accountSlug}/scenarios`}
                            title="Scenario editor"
                            desc="What-if op basisloon of wagen"
                        />
                        <QuickLink
                            href={`/dashboard/${accountSlug}/loonkloof`}
                            title="Loonkloof analyse"
                            desc="Kitagawa + Oaxaca decompositie"
                        />
                    </div>
                </CardContent>
            </Card>

            <p className="text-xs text-muted-foreground">
                Cascade Laag 4b · 9 stappen actief · multi-tenant · POC_UNVERIFIED tarieven vereisen cross-check vóór productie
            </p>
        </div>
    );
}

function SectionCard({
    label,
    value,
    icon: Icon,
    trend,
    footer,
    highlight = false,
}: {
    label: string;
    value: string;
    icon: typeof Users;
    trend?: { direction: "up" | "down"; pct: string; note: string };
    footer?: string;
    highlight?: boolean;
}) {
    const TrendIcon = trend?.direction === "up" ? TrendingUp : TrendingDown;
    const trendColor = trend?.direction === "up" ? "text-emerald-600" : "text-orange-600";
    return (
        <Card className={highlight ? "border-primary/40 shadow-sm" : ""}>
            <CardContent className="pt-6 space-y-3">
                <div className="flex items-center justify-between">
                    <span className="text-xs uppercase tracking-wide text-muted-foreground">{label}</span>
                    <Icon className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="flex items-baseline justify-between gap-2">
                    <div className="text-3xl font-semibold tabular-nums">{value}</div>
                    {trend && (
                        <Badge variant="outline" className={`gap-1 text-xs ${trendColor}`}>
                            <TrendIcon className="h-3 w-3" />
                            {trend.pct}
                        </Badge>
                    )}
                </div>
                {footer && (
                    <p className="text-xs text-muted-foreground leading-relaxed">{footer}</p>
                )}
            </CardContent>
        </Card>
    );
}

function QuickLink({ href, title, desc }: { href: string; title: string; desc: string }) {
    return (
        <Link
            href={href}
            className="group flex items-center justify-between rounded-lg border p-3 hover:bg-muted/50 hover:border-primary/40 transition-colors"
        >
            <div>
                <div className="text-sm font-medium">{title}</div>
                <div className="text-xs text-muted-foreground">{desc}</div>
            </div>
            <ArrowRight className="h-4 w-4 text-muted-foreground group-hover:translate-x-1 group-hover:text-foreground transition-all" />
        </Link>
    );
}
