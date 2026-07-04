#!/usr/bin/env bash
# ISS-035: CI-hook — verifieer dat round_final de enige rounding call-site is
# voor money-precision output in cascade functies.
#
# Scope:
#   Grep alle cascade_* + create_populatie_loonkost + create_simulator_scenario
#   migrations op verboden `round(` calls (buiten round_final).
#
# Allowed round() elsewhere:
#   mart_loonkloof + mart_loonkloof_decomp gebruiken round() voor display/stats
#   (ancienniteit_jaren, gemiddelde uurlonen voor decomp). Deze zijn NIET
#   feed-back naar de cascade en dus toegestaan.
#
# Constitution Principe III MUST (regel 127): rekencascade is deterministisch —
# gegeven identieke input feiten en parametersnapshot, identieke output. Dat
# vereist consistent-afgeronde bedragen op één plaats.
#
# Exit codes:
#   0 = clean
#   1 = illegal round() gevonden in cascade scope

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATIONS_DIR="${ROOT}/supabase/migrations"

# Pattern: files die in-scope zijn voor round_final enforcement.
SCOPE_PATTERN='cascade_stap|cascade_populatie_snapshot|create_populatie_loonkost|create_simulator_scenario'

# Zoek round( calls (niet round_final) in scope files.
violations=$(
    find "$MIGRATIONS_DIR" -name "*.sql" -print \
    | grep -E "$SCOPE_PATTERN" \
    | xargs grep -Hn -E '\bround\s*\(' 2>/dev/null \
    | grep -v 'round_final' \
    || true
)

if [ -n "$violations" ]; then
    echo "ISS-035 violation: cascade scope bevat niet-round_final round() calls:"
    echo ""
    echo "$violations"
    echo ""
    echo "Fix: gebruik public.round_final(bedrag, 'display'|'exact') per Constitution Principe III."
    exit 1
fi

echo "ISS-035 clean: geen illegal round() calls in cascade scope."
exit 0
