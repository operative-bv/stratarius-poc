export type AccountActionState =
    | { status: "idle" }
    | { status: "success"; message: string }
    | { status: "error"; message: string };

export const initialAccountActionState: AccountActionState = { status: "idle" };
