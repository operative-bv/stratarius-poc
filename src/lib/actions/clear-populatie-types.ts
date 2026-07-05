export type ClearPopulatieState = {
    ok: boolean | null;
    message: string | null;
    deletedContracten: number | null;
    deletedPersonen: number | null;
};

export const initialClearPopulatieState: ClearPopulatieState = {
    ok: null,
    message: null,
    deletedContracten: null,
    deletedPersonen: null,
};
