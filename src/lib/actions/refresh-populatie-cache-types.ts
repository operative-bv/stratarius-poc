export type RefreshPopulatieCacheState =
    | { status: "idle" }
    | { status: "success"; rowcount: number }
    | { status: "error"; message: string };

export const initialRefreshPopulatieCacheState: RefreshPopulatieCacheState = { status: "idle" };
