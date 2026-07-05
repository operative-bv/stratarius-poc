export type RefreshMartState =
    | { status: "idle" }
    | { status: "success"; message: string }
    | { status: "error"; message: string };

export const initialRefreshMartState: RefreshMartState = { status: "idle" };
