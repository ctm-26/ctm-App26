#!/usr/bin/env bash
# Treasury Kernel end-to-end CLI test.
# Walks every box of the v0.1 diagram: import gate -> ledger -> rules -> reports -> audit.

set -euo pipefail

cd "$(dirname "$0")/.."

BIN="./treasury"
[[ -x "$BIN" ]] || { echo "missing binary: build first with 'make'"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export TREASURY_DB="$WORK/test.db"

PASS=0
FAIL=0

assert_contains() {
	local needle="$1" haystack="$2" label="$3"
	if grep -qF -- "$needle" <<<"$haystack"; then
		echo "  ok    $label"
		PASS=$((PASS + 1))
	else
		echo "  FAIL  $label"
		echo "        expected substring: $needle"
		echo "        got:"
		sed 's/^/        | /' <<<"$haystack"
		FAIL=$((FAIL + 1))
	fi
}

assert_eq() {
	local got="$1" want="$2" label="$3"
	if [[ "$got" == "$want" ]]; then
		echo "  ok    $label"
		PASS=$((PASS + 1))
	else
		echo "  FAIL  $label"
		echo "        want: $want"
		echo "        got : $got"
		FAIL=$((FAIL + 1))
	fi
}

run() { "$BIN" "$@"; }

echo "step 1: init"
out=$(run init)
assert_contains "initialized" "$out" "init reports success"

echo "step 2: account add + list"
run account add "Chase Checking" checking >/dev/null
run account add "Amex Card" credit >/dev/null
out=$(run account list)
assert_contains "Chase Checking" "$out" "account list shows Chase Checking"
assert_contains "Amex Card" "$out" "account list shows Amex Card"

echo "step 3: dry-run import"
out=$(run import tests/fixtures/sample_chase.csv --account "Chase Checking" --dry-run)
assert_contains "SHOPRITE" "$out" "dry-run previews rows"

echo "step 4: real import"
out=$(run import tests/fixtures/sample_chase.csv --account "Chase Checking")
assert_contains "imported 10 of 10 rows" "$out" "10 rows inserted"

echo "step 5: idempotent import (all duplicates)"
out=$(run import tests/fixtures/sample_chase.csv --account "Chase Checking")
assert_contains "duplicates skipped: 10" "$out" "second import skips all duplicates"

echo "step 6: tx add (manual entry)"
out=$(run tx add --account "Chase Checking" --date 2026-05-15 --desc "MANUAL TEST" --amount -25.50)
assert_contains "added transaction:" "$out" "tx add reports success"
assert_contains "MANUAL TEST" "$out" "tx add echoes description"
out=$(run tx list --account "Chase Checking")
assert_contains "MANUAL TEST" "$out" "tx list shows new manual transaction"

set +e
out=$(run tx add --account "Chase Checking" --date 2026-05-15 --desc "MANUAL TEST" --amount -25.50 2>&1); rc=$?
set -e
assert_eq "$rc" "1" "duplicate tx add -> exit 1"
assert_contains "duplicate" "$out" "duplicate tx add -> readable error"

set +e
out=$(run tx add --account "Chase Checking" --date "not-a-date" --desc "BAD DATE" --amount 1.00 2>&1); rc=$?
set -e
assert_eq "$rc" "1" "bad date -> exit 1"

set +e
out=$(run tx add --date 2026-05-16 --desc "NO ACCOUNT" --amount 1.00 2>&1); rc=$?
set -e
assert_eq "$rc" "2" "missing --account -> exit 2 (usage)"

out=$(run audit --limit 100)
assert_contains "tx.add" "$out" "audit shows tx.add"

echo "step 7: debit/credit CSV format"
out=$(run import tests/fixtures/sample_debit_credit.csv --account "Amex Card")
assert_contains "imported 4 of 4 rows" "$out" "debit/credit CSV imported"

echo "step 8: tx list -- before classification, all unknown"
out=$(run tx list --month 2026-05 --category unknown)
assert_contains "SHOPRITE #421" "$out" "uncategorized tx visible"

echo "step 9: rules"
run category add groceries >/dev/null
run category add gas >/dev/null
run category add subscriptions >/dev/null
run category add income >/dev/null

run rule add SHOPRITE groceries 10 >/dev/null
run rule add SHELL gas 10 >/dev/null
run rule add NETFLIX subscriptions 10 >/dev/null
run rule add SPOTIFY subscriptions 10 >/dev/null
run rule add COSTCO groceries 10 >/dev/null
run rule add PAYROLL income 5 >/dev/null
run rule add SALARY income 5 >/dev/null

out=$(run rule list)
assert_contains "SHOPRITE" "$out" "rule list shows SHOPRITE"
assert_contains "groceries" "$out" "rule list shows groceries"

echo "step 10: classify"
out=$(run classify)
assert_contains "classified" "$out" "classify ran"

echo "step 11: report month"
out=$(run report month 2026-05)
assert_contains "Monthly report: 2026-05" "$out" "report header"
assert_contains "groceries" "$out" "report has groceries"
assert_contains "income" "$out" "report has income"
assert_contains "By account:" "$out" "report has account breakdown"
assert_contains "Chase Checking" "$out" "report shows Chase Checking"
assert_contains "Amex Card" "$out" "report shows Amex Card"

echo "step 12: report on empty month"
out=$(run report month 2025-01)
assert_contains "no transactions" "$out" "empty month is graceful"

echo "step 13: audit trail"
out=$(run audit --limit 100)
assert_contains "init" "$out" "audit shows init"
assert_contains "account.add" "$out" "audit shows account.add"
assert_contains "import" "$out" "audit shows import"
assert_contains "rule.add" "$out" "audit shows rule.add"
assert_contains "classify" "$out" "audit shows classify"
assert_contains "report.month" "$out" "audit shows report.month"

echo "step 14: bad input handling"
set +e
out=$(run report month 2026-13 2>&1); rc=$?
set -e
assert_eq "$rc" "2" "bad month -> exit 2"
assert_contains "invalid month" "$out" "bad month -> readable error"

set +e
out=$(run import tests/fixtures/sample_chase.csv --account "Unknown Account" 2>&1); rc=$?
set -e
assert_eq "$rc" "1" "unknown account -> exit 1"

set +e
out=$(run nonsense 2>&1); rc=$?
set -e
assert_eq "$rc" "2" "unknown command -> exit 2"

echo
echo "=========================="
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo "=========================="
[[ "$FAIL" -eq 0 ]]
