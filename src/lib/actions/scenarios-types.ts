export type ScenarioState = {
    error: string | null;
    redirectTo: string | null;
    successMessage: string | null;
};

export const initialScenarioState: ScenarioState = { error: null, redirectTo: null, successMessage: null };
