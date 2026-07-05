export type AccountActionState = {
    ok: boolean | null;
    message: string | null;
};

export const initialAccountActionState: AccountActionState = { ok: null, message: null };
