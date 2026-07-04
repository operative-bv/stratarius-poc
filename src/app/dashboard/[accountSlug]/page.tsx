import { createClient } from "@/lib/supabase/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Users, Euro, TrendingUp, BarChart3, ArrowRight, GraduationCap, Wrench, Briefcase, Crown } from "lucide-react";
import Link from "next/link";
import { redirect } from "next/navigation";

type PopRow = {
    contract_id: string;
    functienaam: string;
    status: string;
    bruto: number;
    totaal_patronale_kost: number;
    tco: number;
};

function roundFinal(value: number): string {
    const scaled = value * 100;
    const floor = Math.floor(scaled);
    const remainder = scaled - floor;
    let cents: number;
    if (Math.abs(remainder - 0.5) < 1e-9) {
        cents = floor % 2 === 0 ? floor : floor + 1;
    } else {
        cents = Math.round(scaled);
    }
    return (cents / 100).toLocaleString("nl-BE", { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

const TEAM_ICONS: Record<string, typeof Users> = {
    Sales: Briefcase,
    Engineering: Wrench,
    Operations: GraduationCap,
    Management: Crown,
};

export default async function TeamDashboardPage({
    params,
}: {
    params: Promise<{ accountSlug: string }>;
}) {
    const { accountSlug } = await params;
    const supabase = await createClient();

    // Onboarding gate: geen dim_legale_entiteit → naar setup-wizard
    const { data: accountData } = await supabase.rpc("get_account_by_slug", { slug: accountSlug });
    if (accountData?.account_id) {
        const { data: entiteitData } = await supabase
            .from("dim_legale_entiteit")
            .select("legale_entiteit_id")
            .eq("basejump_account_id", accountData.account_id)
            .limit(1);
        if (!entiteitData || entiteitData.length === 0) {
            redirect(`/dashboard/${accountSlug}/setup`);
        }
    }

    // Get scenarios voor default baseline
    const { data: scenariosData } = await supabase
        .from("dim_scenario")
        .select("scenario_id, naam, kind")
        .eq("kind", "baseline")
        .limit(1);
    const baselineId = scenariosData?.[0]?.scenario_id ?? null;

    // Populatie snapshot voor huidige maand (default 2024-06-01 demo)
    const { data } = await supabase.rpc("cascade_populatie_snapshot", {
        p_periode: "2024-06-01",
        p_scenario_id: baselineId,
    });
    const rows = (data ?? []) as PopRow[];

    const headcount = rows.length;
    const totalBruto = rows.reduce((s, r) => s + Number(r.bruto), 0);
    const totalPatronale = rows.reduce((s, r) => s + Number(r.totaal_patronale_kost), 0);
    const totalTco = rows.reduce((s, r) => s + Number(r.tco), 0);
    const patronalePct = totalBruto > 0 ? (totalPatronale / totalBruto) * 100 : 0;

    // Group per team
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

    // Group per status
    const statuses = new Map<string, number>();
    for (const r of rows) statuses.set(r.status, (statuses.get(r.status) ?? 0) + 1);

    return (
        <div className="mx-auto max-w-7xl py-8 space-y-6">
            <div>
                <h1 className="text-3xl font-bold">Werkgeverskost overzicht</h1>
                <p className="text-muted-foreground text-sm mt-1">
                    Baseline scenario · periode juni 2024 · alle {headcount} medewerkers
                </p>
            </div>

            {/* KPI cards */}
            <div className="grid gap-4 md:grid-cols-4">
                <KpiCard icon={Users} label="Headcount" value={headcount.toString()} sub={Array.from(statuses.entries()).map(([s, c]) => `${c} ${s}`).join(" · ")} />
                <KpiCard icon={Euro} label="Bruto loonsom" value={`€ ${roundFinal(totalBruto)}`} sub="per maand" />
                <KpiCard icon={BarChart3} label="Patronale kost" value={`€ ${roundFinal(totalPatronale)}`} sub={`${patronalePct.toFixed(1)}% van bruto`} />
                <KpiCard icon={TrendingUp} label="Totaal TCO" value={`€ ${roundFinal(totalTco)}`} sub="werkgeverskost totaal" highlight />
            </div>

            {/* Team breakdown + donut chart */}
            <div className="grid gap-4 md:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2">
                            <Users className="h-5 w-5" />
                            TCO per team
                        </CardTitle>
                    </CardHeader>
                    <CardContent>
                        <div className="flex items-center gap-6">
                            <DonutChart data={teamRows.map(([name, stats]) => ({ name, value: stats.tco }))} total={totalTco} />
                            <div className="space-y-3 flex-1">
                                {teamRows.map(([name, stats], idx) => {
                                    const Icon = TEAM_ICONS[name] ?? Users;
                                    const pct = totalTco > 0 ? (stats.tco / totalTco) * 100 : 0;
                                    return (
                                        <div key={name} className="flex items-center justify-between border-b pb-2 last:border-0">
                                            <div className="flex items-center gap-2">
                                                <div className="w-3 h-3 rounded-sm" style={{ backgroundColor: DONUT_COLORS[idx % DONUT_COLORS.length] }} />
                                                <Icon className="h-3.5 w-3.5 text-muted-foreground" />
                                                <div className="text-sm font-medium">{name}</div>
                                            </div>
                                            <div className="text-right">
                                                <div className="text-xs font-semibold tabular-nums">{pct.toFixed(0)}%</div>
                                                <div className="text-xs text-muted-foreground">€ {roundFinal(stats.tco)}</div>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle>Snel naar</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-3">
                        <QuickLink href={`/dashboard/${accountSlug}/populatie`} title="Populatie snapshot" desc="Alle contracten, filter op team en scenario" />
                        <QuickLink href={`/dashboard/${accountSlug}/populatie?compare=1&scenario=${baselineId}`} title="What-if analyse" desc="Vergelijk scenarios met baseline" />
                        <QuickLink href={`/dashboard/${accountSlug}/simulator`} title="Individuele simulator" desc="Simuleer één contract met parameters" />
                    </CardContent>
                </Card>
            </div>

            <div className="text-xs text-muted-foreground">
                Cascade Phase 5 stap 1-7 actief · Loonkloof-mart Phase 6 · UI Phase 7 · POC subset (exclusief stap 4 doelgroepverminderingen op dashboard-niveau, stap 8-9 wagen + arbeidsongevallen)
            </div>
        </div>
    );
}

function KpiCard({ icon: Icon, label, value, sub, highlight = false }: { icon: typeof Users; label: string; value: string; sub: string; highlight?: boolean }) {
    return (
        <Card className={highlight ? "bg-secondary" : ""}>
            <CardContent className="pt-6">
                <div className="flex items-center justify-between">
                    <span className="text-xs text-muted-foreground uppercase tracking-wide">{label}</span>
                    <Icon className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="text-2xl font-semibold mt-2 tabular-nums">{value}</div>
                <div className="text-xs text-muted-foreground mt-1">{sub}</div>
            </CardContent>
        </Card>
    );
}

const DONUT_COLORS = ["#3b82f6", "#8b5cf6", "#10b981", "#f59e0b", "#ec4899", "#06b6d4", "#f43f5e"];

function DonutChart({ data, total }: { data: { name: string; value: number }[]; total: number }) {
    const size = 160;
    const strokeWidth = 28;
    const radius = (size - strokeWidth) / 2;
    const circumference = 2 * Math.PI * radius;
    let cumulative = 0;
    return (
        <div className="relative" style={{ width: size, height: size }}>
            <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
                <circle cx={size / 2} cy={size / 2} r={radius} fill="none" stroke="hsl(var(--muted))" strokeWidth={strokeWidth} />
                {data.map((d, i) => {
                    const value = d.value / total;
                    const dash = value * circumference;
                    const offset = cumulative * circumference;
                    cumulative += value;
                    return (
                        <circle
                            key={d.name}
                            cx={size / 2}
                            cy={size / 2}
                            r={radius}
                            fill="none"
                            stroke={DONUT_COLORS[i % DONUT_COLORS.length]}
                            strokeWidth={strokeWidth}
                            strokeDasharray={`${dash} ${circumference}`}
                            strokeDashoffset={-offset}
                        />
                    );
                })}
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
                <div className="text-xs text-muted-foreground">TCO</div>
                <div className="text-sm font-semibold tabular-nums">€ {(total / 1000).toFixed(0)}k</div>
            </div>
        </div>
    );
}

function QuickLink({ href, title, desc }: { href: string; title: string; desc: string }) {
    return (
        <Link href={href} className="flex items-center justify-between rounded-lg border p-3 hover:bg-muted/40 transition-colors group">
            <div>
                <div className="text-sm font-medium">{title}</div>
                <div className="text-xs text-muted-foreground">{desc}</div>
            </div>
            <ArrowRight className="h-4 w-4 text-muted-foreground group-hover:translate-x-1 transition-transform" />
        </Link>
    );
}
