// ISS-097: types voor populatie-page — geëxtraheerd uit row-detail-sheet.tsx
// zodat server components (populatie-results.tsx) niet client-only bestand
// hoeven te importeren voor pure types. Convergent met memory rule
// "use server alleen async functions" en de bredere "types in -types.ts"
// conventie.

export type PopRow = {
    contract_id: string;
    persoon_id: string;
    pc_id: string;
    status: string;
    werkgeverscategorie: number;
    functienaam: string;
    bruto: number;
    stap2_basis_rsz: number;
    stap3_vermindering: number;
    stap5_bijzondere: number;
    stap6_vakantiegeld: number;
    stap7_extralegaal: number;
    totaal_patronale_kost: number;
    tco: number;
};

export type RSZParam = {
    status: string;
    werkgeverscategorie: number;
    basisbijdrage_pct: number;
    basisfactor_pct: number;
    bron_url: string;
};

export type StructureleParam = {
    werkgeverscategorie: number;
    forfait: number;
    coefficient_a: number;
    coefficient_b: number;
    drempel_s0: number;
    drempel_s1: number;
    bron_url: string;
};

export type ExtralegaalDetail = {
    component_id: string;
    name: string;
    bedrag: number;
    bron_ref: string | null;
};
