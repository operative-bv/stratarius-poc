"use client";

import * as React from "react";
import { format, parseISO } from "date-fns";
import { nl } from "date-fns/locale";
import { CalendarIcon } from "lucide-react";
import { Calendar } from "@/components/ui/calendar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

/**
 * shadcn canonical date-picker pattern (Popover + Calendar).
 * Rendert als knop met kalender-icoon + datum in NL locale.
 * Serialiseert als YYYY-MM-DD via een hidden input (form-compatible).
 */
export function DatePicker({
    name,
    defaultValue,
    placeholder = "Kies datum",
    id,
    className,
}: {
    name: string;
    defaultValue?: string; // YYYY-MM-DD
    placeholder?: string;
    id?: string;
    className?: string;
}) {
    const [date, setDate] = React.useState<Date | undefined>(
        defaultValue ? parseISO(defaultValue) : undefined,
    );
    const [open, setOpen] = React.useState(false);

    const serialized = date ? format(date, "yyyy-MM-dd") : "";

    return (
        <>
            <Popover open={open} onOpenChange={setOpen}>
                <PopoverTrigger asChild>
                    <Button
                        id={id}
                        type="button"
                        variant="outline"
                        className={cn(
                            "w-full justify-start text-left font-normal",
                            !date && "text-muted-foreground",
                            className,
                        )}
                    >
                        <CalendarIcon className="mr-2 size-4" />
                        {date ? format(date, "d MMMM yyyy", { locale: nl }) : placeholder}
                    </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                    <Calendar
                        mode="single"
                        selected={date}
                        onSelect={(d) => {
                            setDate(d);
                            setOpen(false);
                        }}
                        locale={nl}
                        weekStartsOn={1}
                    />
                </PopoverContent>
            </Popover>
            <input type="hidden" name={name} value={serialized} />
        </>
    );
}
