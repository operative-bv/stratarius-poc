// Discriminated union: 3 zinvolle states expliciet, geen ongeldige combinaties
// mogelijk (bijv. status='error' met deletedContracten was voorheen typebaar).
export type ClearPopulatieState =
    | { status: "idle" }
    | { status: "success"; deletedContracten: number; deletedPersonen: number }
    | { status: "error"; message: string };

export const initialClearPopulatieState: ClearPopulatieState = { status: "idle" };
