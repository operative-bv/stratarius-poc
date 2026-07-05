"use client";

import { Area, AreaChart, CartesianGrid, XAxis } from "recharts";
import {
    ChartConfig,
    ChartContainer,
    ChartLegend,
    ChartLegendContent,
    ChartTooltip,
    ChartTooltipContent,
} from "@/components/ui/chart";

const chartConfig = {
    bruto: {
        label: "Bruto loonsom",
        color: "hsl(var(--chart-1))",
    },
    patronaal: {
        label: "Patronale kost",
        color: "hsl(var(--chart-2))",
    },
} satisfies ChartConfig;

export default function LoonkostChart({
    data,
}: {
    data: { maand: string; bruto: number; patronaal: number }[];
}) {
    return (
        <ChartContainer config={chartConfig} className="aspect-auto h-[260px] w-full">
            <AreaChart data={data} margin={{ left: 12, right: 12, top: 8 }}>
                <defs>
                    <linearGradient id="fillBruto" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="var(--color-bruto)" stopOpacity={0.85} />
                        <stop offset="100%" stopColor="var(--color-bruto)" stopOpacity={0.05} />
                    </linearGradient>
                    <linearGradient id="fillPatronaal" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="var(--color-patronaal)" stopOpacity={0.7} />
                        <stop offset="100%" stopColor="var(--color-patronaal)" stopOpacity={0.05} />
                    </linearGradient>
                </defs>
                <CartesianGrid vertical={false} strokeDasharray="3 3" />
                <XAxis
                    dataKey="maand"
                    tickLine={false}
                    axisLine={false}
                    tickMargin={8}
                    minTickGap={16}
                />
                <ChartTooltip
                    cursor={false}
                    content={
                        <ChartTooltipContent
                            indicator="dot"
                            labelFormatter={(v) => `Maand: ${v}`}
                            formatter={(value, name) => [
                                <span key="v" className="tabular-nums font-medium">
                                    € {Number(value).toLocaleString("nl-BE", { maximumFractionDigits: 0 })}
                                </span>,
                                " ",
                                <span key="n" className="text-muted-foreground">
                                    {chartConfig[name as keyof typeof chartConfig]?.label}
                                </span>,
                            ]}
                        />
                    }
                />
                <Area
                    dataKey="patronaal"
                    type="monotone"
                    fill="url(#fillPatronaal)"
                    stroke="var(--color-patronaal)"
                    stackId="a"
                />
                <Area
                    dataKey="bruto"
                    type="monotone"
                    fill="url(#fillBruto)"
                    stroke="var(--color-bruto)"
                    stackId="a"
                />
                <ChartLegend content={<ChartLegendContent />} />
            </AreaChart>
        </ChartContainer>
    );
}
