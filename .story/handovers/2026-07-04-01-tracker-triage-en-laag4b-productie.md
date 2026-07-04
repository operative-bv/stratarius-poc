Sessie 2026-07-04: Tracker-triage + fase Laag 4b.

## Wat is er gebeurd

Gestart met 74 open issues (debt-trend +174%). Ontdekt dat ~72% van de issues geen echte openstaande problemen waren maar procesartefacten uit review-flows: "Verplaatst naar T-XXX" markers, "Filed als ISS-XXX" duplicaten, en "Non-blocking. [reden]" scope-beslissingen.

Triage in 3 buckets:
- Bucket A: 9 duplicate markers → gesloten met verwijzing naar canonical.
- Bucket B: 40 "accepted-for-poc" scope-beslissingen → gesloten met verwijzing naar nieuwe lessons.
- Bucket C: 20 echte follow-ups → open gehouden. Daarvan 7 (cluster productie-uitbreiding) gepromoot naar tickets in nieuwe fase.

Eind: 13 open issues (allemaal actionable) + 7 nieuwe tickets in fase "Laag 4b: Productie".

## Nieuwe fase: Laag 4b: Productie (7 tickets)

- T-045: Doelgroepverminderingen non-cumulatie policy (Belgische wet) — uit ISS-060
- T-046: Bijzondere bijdragen toepassing + centenindex — uit ISS-063
- T-047: Eindejaarspremie functie + param_eindejaarspremie tabel — uit ISS-065
- T-048: Cascade stap 8 wagen/mobiliteit (CO2-VAA) — uit ISS-066
- T-049: Cascade stap 9 arbeidsongevallenverzekering — uit ISS-067
- T-050: Persistent audit_log + GDPR-reads instrumentatie — uit ISS-071
- T-051: Simulator v1 synthetic contract flow — uit ISS-073

Deze fase is heterogeen (cascade + infra + UI) maar bindt via "wat POC nog niet af had voor productie".

## Nieuwe lessons (voor toekomstige sessies)

- L-001: POC scope-beslissingen horen niet in de issue tracker → sluit met accepted-for-poc en link naar lesson.
- L-002: Cascade-functies propageren SQL NULL intentioneel. Detectie is caller-side (T-029 orchestrator).
- L-003: T-029 orchestrator owns cross-function validation & missing-test coverage.
- L-004: Sluit "Verplaatst naar" en "Filed als" markers direct bij creatie canonical (had +14 op tracker voorkomen).

## Nog open op tafel — 3 strategische vragen van user

1. Is dit systeem multi-tenant klaar? (RLS, tenant scoping over dim_/fact_/param_/mart_ heen)
2. Hoe gaan we om met veranderende parameters/formules zonder historische data te breken? (effective-dating patroon)
3. Simulaties op (deel van) populatie én individueel niveau — wat is er al, wat mist?

User opende api/oaxaca.py — mogelijk relevant voor vraag 3 (populatie-analyse via Python endpoint).

Volgende sessie: analyse van deze 3 vragen leidt waarschijnlijk tot extra tickets in Laag 4b of nieuwe fase.

## State

- Tickets: 44/51 complete, 7 open in Laag 4b
- Issues: 13 open (UI polish 4 + bouwstenen 5 + schema hardening 4)
- Lessons: 4 active (L-001..L-004)
- Snapshot: fresh (was 81 commits stale)
- Handovers: 35 (deze)