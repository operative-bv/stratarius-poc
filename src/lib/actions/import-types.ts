export type ImportState = {
    error: string | null;
    result: { created: number; skipped: number; errors: string[] } | null;
};

export const initialImportState: ImportState = { error: null, result: null };
