/**
 * Client-side mirrors van cascade pure functions.
 *
 * Deze module bevat TypeScript implementaties die byte-identical output geven
 * met hun Postgres-tegenhangers. Ze bestaan om UI-simulator round-trips te
 * vermijden voor snelle preview-berekeningen (ISS-033 uurloon, ISS-036 round_final).
 *
 * Constitution Principe III MUST: rekencascade is deterministisch. Deze mirrors
 * moeten in-sync blijven met de SQL implementaties — bij afwijking krijgt de
 * client andere cijfers dan de DB, wat "silent divergence" veroorzaakt.
 *
 * Testen: pgTAP tests dekken de SQL kant; TypeScript tests zouden matched-output
 * moeten valideren. Ontbrekende TS test-suite is ISS-follow-up (opt).
 */

export interface RoundFinalOptions {
    /** Placeholder wanneer input null/undefined is (default "—") */
    placeholder?: string;
    /** Aantal decimalen in output (default 2 cent-precision, 0 voor whole-EUR display) */
    digits?: 0 | 2;
}

/**
 * Client-side mirror van public.round_final(bedrag, 'display').
 *
 * Postgres round() = half-away-from-zero. Banker's rounding = half-to-even,
 * DMFA-conform per KB 28/11/1969 art. 34. Gebruikt in cascade output display.
 *
 * Voor cent-precision (digits=2, default): banker's rounding op de cent.
 * Voor whole-EUR display (digits=0): Math.round (half-away-from-zero) — banker's
 *   op EUR-schaal is niet gestandaardiseerd, aggregate weergave laat conventionele
 *   ronding toe.
 *
 * @param value Bedrag in EUR (kan negatief zijn)
 * @param options placeholder + digits (default {placeholder: "—", digits: 2})
 * @returns Bedrag geformatteerd volgens Belgische locale
 */
export function roundFinal(
    value: number | null | undefined,
    options: RoundFinalOptions = {}
): string {
    const { placeholder = "—", digits = 2 } = options;
    if (value === null || value === undefined || Number.isNaN(value)) return placeholder;

    if (digits === 0) {
        // Whole-EUR display voor aggregates (dashboard). Geen banker's.
        return Math.round(value).toLocaleString("nl-BE", {
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
        });
    }

    // digits === 2 → banker's op cent-precisie (DMFA-conform).
    const scaled = value * 100;
    const floor = Math.floor(scaled);
    const remainder = scaled - floor;
    let cents: number;
    if (Math.abs(remainder - 0.5) < 1e-9) {
        cents = floor % 2 === 0 ? floor : floor + 1;
    } else {
        cents = Math.round(scaled);
    }
    return (cents / 100).toLocaleString("nl-BE", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

/**
 * Client-side mirror van public.uurloon_van_maandloon(maandloon, pc_id, periode).
 *
 * Belgische conventie (PDF Laag 3):
 *   uurloon = (maandloon × 3) / (13 × gemiddelde_wekelijkse_uren)
 *
 * De PC/periode lookup naar param_arbeidsduur.gemiddelde_wekelijkse_uren gebeurt
 * caller-side (via supabase.from("param_arbeidsduur")…). Deze functie is puur
 * numeriek — geen DB-round-trip nodig.
 *
 * @param maandloon Bruto maandloon in EUR
 * @param gemiddeldeWekelijkseUren Uren per week uit param_arbeidsduur (bv. 38 voor PC 200)
 * @returns Uurloon in EUR, of null wanneer input incompleet
 */
export function uurloonVanMaandloon(
    maandloon: number | null | undefined,
    gemiddeldeWekelijkseUren: number | null | undefined
): number | null {
    if (maandloon === null || maandloon === undefined || Number.isNaN(maandloon)) return null;
    if (
        gemiddeldeWekelijkseUren === null ||
        gemiddeldeWekelijkseUren === undefined ||
        Number.isNaN(gemiddeldeWekelijkseUren) ||
        gemiddeldeWekelijkseUren <= 0
    ) {
        return null;
    }
    return (maandloon * 3) / (13 * gemiddeldeWekelijkseUren);
}
