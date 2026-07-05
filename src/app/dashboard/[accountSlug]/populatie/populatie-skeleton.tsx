import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

const COLS = [
    "Contract",
    "Team",
    "Status",
    "PC",
    "Bruto",
    "Basis RSZ",
    "Vermindering",
    "Bijzondere",
    "Vakantiegeld",
    "Extralegaal",
    "Patronaal",
    "TCO",
    "",
];

export default function PopulatieSkeleton() {
    return (
        <Card>
            <CardContent className="pt-6 overflow-x-auto">
                <Table>
                    <TableHeader>
                        <TableRow>
                            {COLS.map((c) => (
                                <TableHead key={c}>{c}</TableHead>
                            ))}
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {Array.from({ length: 10 }).map((_, i) => (
                            <TableRow key={i}>
                                {COLS.map((_c, j) => (
                                    <TableCell key={j}>
                                        <Skeleton className="h-4 w-full" />
                                    </TableCell>
                                ))}
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
                <p className="text-xs text-muted-foreground mt-4 flex items-center gap-2">
                    <Skeleton className="h-3 w-3 rounded-full" />
                    Cascade berekening loopt...
                </p>
            </CardContent>
        </Card>
    );
}
