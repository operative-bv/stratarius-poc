import type { OaxacaResult } from "@/lib/oaxaca-client";

export type OaxacaState = {
    result: OaxacaResult | null;
    error: string | null;
};

export const initialOaxacaState: OaxacaState = { result: null, error: null };
