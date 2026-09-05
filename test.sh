#!/usr/bin/env bash
# ============================================================================
# test.sh — test suite for feast-of-weeks
#
# Runs the built binary against a table of (input date, expected output date)
# pairs and reports pass/fail for each. Expected values were computed
# independently against Howard Hinnant's civil_from_days/days_from_civil
# reference algorithm, so this checks the assembly's leap-year handling
# (including the tricky "divisible by 100 but not 400" century rule),
# month/year rollovers, and leap-day (Feb 29) inputs.
#
# Usage:
#   ./build.sh          # make sure the binary is built first
#   ./test.sh
# ============================================================================

set -u

BIN="./feast-of-weeks"

if [[ ! -x "$BIN" ]]; then
    echo "error: $BIN not found or not executable — run ./build.sh first" >&2
    exit 1
fi

# input_date expected_output_date
TESTS=(
    "2000-01-11 2000-02-29"   # century leap year (div by 400) -> Feb 29 exists
    "1900-01-11 1900-03-01"   # century NON-leap year (div by 100, not 400) -> no Feb 29
    "2024-02-01 2024-03-21"   # regular leap year, starting in Feb
    "2023-02-01 2023-03-22"   # regular non-leap year, starting in Feb
    "2004-02-29 2004-04-18"   # input itself is a leap day
    "2020-02-29 2020-04-18"   # another leap-day input
    "2024-12-15 2025-02-02"   # crosses a year boundary
    "1999-12-15 2000-02-02"   # crosses the Y2K year boundary
    "2100-01-01 2100-02-19"   # century non-leap (2100 not div by 400)
    "2026-09-04 2026-10-23"   # arbitrary everyday case
)

pass=0
fail=0

for t in "${TESTS[@]}"; do
    input="${t%% *}"
    expected="${t##* }"
    actual="$("$BIN" "$input")"
    actual="${actual%$'\n'}"   # strip trailing newline for comparison

    if [[ "$actual" == "$expected" ]]; then
        printf "PASS  %s -> %s\n" "$input" "$actual"
        ((pass++))
    else
        printf "FAIL  %s -> got %s, expected %s\n" "$input" "$actual" "$expected"
        ((fail++))
    fi
done

echo "----------------------------------------"
echo "$pass passed, $fail failed (of ${#TESTS[@]})"

[[ $fail -eq 0 ]]
