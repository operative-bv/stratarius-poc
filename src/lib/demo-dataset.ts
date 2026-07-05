// Deterministische generator voor demo populatie (POC). Zelfde output elke run.
// Belgische naam-pool + realistische distributie functies/opleiding/leeftijd/salaris.

import type { Geslacht, Opleidingsniveau, Status } from "./domain-types";

export type DemoRow = {
    naam: string;
    geslacht: Geslacht;
    geboortedatum: string; // YYYY-MM-DD
    opleidingsniveau: Opleidingsniveau;
    team: string;
    status: Status;
    pc: string;
    bruto: number;
};

const VOORNAMEN_M = [
    "Bram", "Kevin", "Michiel", "Thomas", "Jonas", "Wout", "Lars", "Niels", "Jan", "Pieter",
    "Tim", "Bart", "Koen", "Sven", "Dries", "Robin", "Karel", "Dirk", "Steven", "Peter",
    "Filip", "Luc", "Marc", "Rik", "Stefan", "Yannick", "David", "Nick", "Sam", "Bert",
    "Jeroen", "Kobe", "Milan", "Arne", "Simon", "Matthias", "Andreas", "Christof", "Willem", "Frederik",
];
const VOORNAMEN_V = [
    "Eva", "Sofie", "Emma", "Julie", "Nele", "Ines", "Femke", "Lotte", "Anke", "Sara",
    "Lien", "Charlotte", "Marie", "Hanne", "Elisabeth", "Ilse", "An", "Tine", "Katrien", "Nathalie",
    "Kim", "Els", "Sarah", "Britt", "Elke", "Karolien", "Silke", "Maaike", "Griet", "Ellen",
    "Fien", "Hilde", "Kaat", "Lisa", "Maité", "Rita", "Vera", "Wendy", "Bieke", "Christel",
];
const ACHTERNAMEN = [
    "Peeters", "Janssens", "Maes", "Jacobs", "Willems", "Mertens", "Claes", "Wouters",
    "Goossens", "De Smet", "De Vries", "De Vos", "De Cock", "De Backer", "De Wilde", "De Ridder",
    "Van den Berg", "Van Damme", "Van Hoof", "Vermeulen", "Verhaeghe", "Verhoeven", "Verbeke",
    "Aerts", "Bogaerts", "Beckers", "Bruynseels", "Claessens", "Coppens", "Cools",
    "Daems", "Dubois", "Dhondt", "Engelen", "Fabri", "Gielen", "Hermans", "Hendrickx",
    "Lemmens", "Michielsen", "Nys", "Ooms", "Pauwels", "Segers", "Simoens", "Smet",
    "Thys", "Van Acker", "Van Camp", "Van Hoorde", "Verhaegen", "Verstraete", "Vranken", "Wauters",
];

const TEAMS_DISTR: { team: string; weight: number }[] = [
    { team: "Sales", weight: 30 },
    { team: "Engineering", weight: 25 },
    { team: "Operations", weight: 20 },
    { team: "Marketing", weight: 15 },
    { team: "Management", weight: 10 },
];

const OPLEIDING_DISTR: { opl: DemoRow["opleidingsniveau"]; weight: number }[] = [
    { opl: "hooggeschoold", weight: 30 },
    { opl: "middel_geschoold", weight: 60 },
    { opl: "laaggeschoold", weight: 10 },
];

// Team-basis salaris (bruto/maand) — bij middel_geschoold + 5 jaar ervaring
const TEAM_BASE_SALARY: Record<string, number> = {
    Sales: 3200,
    Engineering: 3800,
    Operations: 2800,
    Marketing: 3000,
    Management: 5000,
};

// Simple seeded LCG voor deterministische output
function makeRng(seed: number) {
    let state = seed;
    return () => {
        state = (state * 1664525 + 1013904223) % 4294967296;
        return state / 4294967296;
    };
}

function weightedPick<T>(items: { weight: number }[] & { [K in number]: T }, rnd: () => number): T {
    const total = items.reduce((s, it) => s + it.weight, 0);
    let r = rnd() * total;
    for (const it of items) {
        r -= it.weight;
        if (r <= 0) return it as unknown as T;
    }
    return items[items.length - 1] as unknown as T;
}

function pick<T>(arr: T[], rnd: () => number): T {
    return arr[Math.floor(rnd() * arr.length)];
}

export function generateDemoRows(count = 1000): DemoRow[] {
    const rnd = makeRng(20260705);
    const rows: DemoRow[] = [];
    const seenNames = new Set<string>();

    for (let i = 0; i < count; i++) {
        // Geslacht 50/50 (bij nulhypothese; loonkloof komt uit salarisdistributie
        // niet uit geslachtsverdeling)
        const geslacht: "m" | "v" = rnd() < 0.5 ? "m" : "v";
        const voornaam = geslacht === "m" ? pick(VOORNAMEN_M, rnd) : pick(VOORNAMEN_V, rnd);
        const achternaam = pick(ACHTERNAMEN, rnd);
        let naam = `${voornaam} ${achternaam}`;
        // Voeg suffix toe bij dubbele namen zodat unique in demo
        if (seenNames.has(naam)) {
            let n = 2;
            while (seenNames.has(`${naam} ${n}`)) n++;
            naam = `${naam} ${n}`;
        }
        seenNames.add(naam);

        // Leeftijd 22-60 (bell curve rond 38)
        const leeftijd = Math.round(38 + (rnd() + rnd() + rnd() - 1.5) * 12);
        const clampedLft = Math.max(22, Math.min(60, leeftijd));
        const geboortejaar = 2024 - clampedLft;
        const geboortedatum = `${geboortejaar}-${String(1 + Math.floor(rnd() * 12)).padStart(2, "0")}-${String(1 + Math.floor(rnd() * 28)).padStart(2, "0")}`;

        const opl = weightedPick<{ opl: DemoRow["opleidingsniveau"]; weight: number }>(
            OPLEIDING_DISTR,
            rnd,
        ).opl;
        const teamPick = weightedPick<{ team: string; weight: number }>(TEAMS_DISTR, rnd).team;

        // Management vereist typisch hoge leeftijd + hoog opleiding
        const isManagement = teamPick === "Management";
        const status: "bediende" | "arbeider" =
            teamPick === "Operations" && rnd() < 0.35 ? "arbeider" : "bediende";
        const pc = status === "arbeider" ? "124" : "200";

        // Salarisformule: base(team) + ervaring + opleiding + gender-gap simulatie
        const ervaring = Math.max(0, clampedLft - 22 - (opl === "hooggeschoold" ? 5 : opl === "middel_geschoold" ? 2 : 0));
        const opleidingBonus =
            opl === "hooggeschoold" ? 600 : opl === "laaggeschoold" ? -300 : 0;
        const ervaringBonus = ervaring * 45;
        const managementBonus = isManagement ? 1800 : 0;
        // Kleine loonkloof (simuleert reële populatie): ~3% gap vrouwen
        const genderPenalty = geslacht === "v" ? -80 : 0;
        // Noise ±5%
        const noise = (rnd() - 0.5) * 400;

        let bruto = Math.round(
            (TEAM_BASE_SALARY[teamPick] ?? 3000) +
                opleidingBonus +
                ervaringBonus +
                managementBonus +
                genderPenalty +
                noise,
        );

        // Klemwaarde: minimum €2200 zoals gevraagd
        bruto = Math.max(2200, bruto);

        rows.push({
            naam,
            geslacht,
            geboortedatum,
            opleidingsniveau: opl,
            team: teamPick,
            status,
            pc,
            bruto,
        });
    }

    return rows;
}
