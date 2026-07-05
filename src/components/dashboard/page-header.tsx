import * as React from "react";

export function PageHeader({
    title,
    description,
    icon: Icon,
    actions,
}: {
    title: React.ReactNode;
    description?: React.ReactNode;
    icon?: React.ComponentType<{ className?: string }>;
    actions?: React.ReactNode;
}) {
    return (
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex items-start gap-3">
                {Icon && (
                    <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-muted text-foreground">
                        <Icon className="h-5 w-5" />
                    </div>
                )}
                <div className="space-y-1">
                    <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
                    {description && (
                        <p className="text-sm text-muted-foreground">{description}</p>
                    )}
                </div>
            </div>
            {actions && <div className="flex items-center gap-2 shrink-0">{actions}</div>}
        </div>
    );
}
