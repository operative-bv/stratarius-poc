export type RefreshMartState = {
    ok: boolean | null;
    message: string | null;
};

export const initialRefreshMartState: RefreshMartState = { ok: null, message: null };
