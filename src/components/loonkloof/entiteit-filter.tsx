"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Label } from "@/components/ui/label";

type Entiteit = { legale_entiteit_id: string; naam: string };

export default function EntiteitFilter({
    accountSlug,
    entiteiten,
    activeEntiteitId,
}: {
    accountSlug: string;
    entiteiten: Entiteit[];
    activeEntiteitId: string | null;
}) {
    const router = useRouter();
    const [value, setValue] = useState<string>(activeEntiteitId ?? "all");

    const handleChange = (next: string) => {
        setValue(next);
        const suffix = next === "all" ? "" : `?entiteit=${encodeURIComponent(next)}`;
        router.push(`/dashboard/${accountSlug}/loonkloof${suffix}`);
    };

    return (
        <div className="flex flex-col sm:flex-row sm:items-center gap-3">
            <Label htmlFor="entiteit-filter" className="text-xs uppercase text-muted-foreground shrink-0">
                Legale entiteit
            </Label>
            <Select value={value} onValueChange={handleChange}>
                <SelectTrigger id="entiteit-filter" className="w-full sm:w-72">
                    <SelectValue />
                </SelectTrigger>
                <SelectContent>
                    <SelectItem value="all">
                        Alle {entiteiten.length} entiteiten (gemiddelde)
                    </SelectItem>
                    {entiteiten.map((e) => (
                        <SelectItem key={e.legale_entiteit_id} value={e.legale_entiteit_id}>
                            {e.naam}
                        </SelectItem>
                    ))}
                </SelectContent>
            </Select>
        </div>
    );
}
