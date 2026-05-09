#!/usr/bin/env bash
# End-to-end smoke test. DEV ONLY: wipes data/*.dat before running.
# Usage: scripts/smoke-test.sh
#        PORT=9000 scripts/smoke-test.sh
#        BASE=http://host scripts/smoke-test.sh

set -euo pipefail

PORT="${PORT:-8080}"
BASE="${BASE:-http://127.0.0.1:${PORT}}"
CGI="${BASE}/cgi-bin"
COOKIES="$(mktemp -t cobill-smoke-cookies.XXXXXX)"
trap 'rm -f "$COOKIES"' EXIT

curl() { command curl -b "$COOKIES" -c "$COOKIES" "$@"; }

pass() { printf "  \033[32m✓\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m  %s\n" "$1"; printf "     %s\n" "$2"; exit 1; }

step() { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

assert_contains() {
    local body="$1" needle="$2" desc="$3"
    if grep -qF "$needle" <<<"$body"; then
        pass "$desc"
    else
        fail "$desc" "expected to find: $needle"
    fi
}

assert_not_contains() {
    local body="$1" needle="$2" desc="$3"
    if grep -qF "$needle" <<<"$body"; then
        fail "$desc" "unexpected: $needle"
    else
        pass "$desc"
    fi
}

assert_status() {
    local code="$1" expected="$2" desc="$3"
    if [[ "$code" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc" "got HTTP $code, expected $expected"
    fi
}

step "Server reachable"
curl -sSf -o /dev/null "$BASE/" \
    && pass "GET / -> 200" \
    || fail "GET /" "dev server not responding on $BASE"

step "Reset data dir"
rm -f data/clients.dat data/clients.dat.* \
      data/invoices.dat data/invoices.dat.* \
      data/sessions.dat data/sessions.dat.*
pass "data files removed"

step "Auth gate"
http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
    "${CGI}/client?action=list")
assert_status "$http_code" "302" "unauthenticated CGI redirects"

http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST -d "username=admin&password=wrong" \
    "${CGI}/auth?action=login")
assert_status "$http_code" "401" "wrong password rejected"

http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST -d "username=admin&password=cobill" \
    "${CGI}/auth?action=login")
assert_status "$http_code" "302" "good password issues 302 + cookie"

grep -q "COBILL_SID" "$COOKIES" \
    && pass "Set-Cookie captured" \
    || fail "Set-Cookie capture" "no COBILL_SID in $COOKIES"

http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
    "${CGI}/client?action=list")
assert_status "$http_code" "200" "authenticated CGI now serves 200"

step "Client CRUD"
body=$(curl -sS -X POST -d \
    "action=create&name=Smoke+SARL&siret=11122233344455&city=Lyon&country=France" \
    "${CGI}/client")
assert_contains "$body" "Smoke SARL" "create returns refreshed list"
assert_contains "$body" "CLI-000001" "auto-id starts at 000001"

body=$(curl -sS "${CGI}/client?action=list")
assert_contains "$body" "0001 client(s)" "list shows count=1"

body=$(curl -sS "${CGI}/client?action=get&id=CLI-000001")
assert_contains "$body" "EDIT CLIENT" "get returns edit form"
assert_contains "$body" "value='Smoke SARL'" "edit form prefilled"

body=$(curl -sS -X POST -d \
    "action=update&id=CLI-000001&name=Smoke+SARL+%5BEDITED%5D&city=Lyon&country=France&siret=11122233344455" \
    "${CGI}/client")
assert_contains "$body" "Smoke SARL [EDITED]" "update reflects in list"

step "Invoice creation + decimal correctness"
body=$(curl -sS -X POST -d \
    "action=create&client_id=CLI-000001&date=2026-05-01&due_date=2026-05-31&tva_rate=0.20&desc01=Web+development&qty01=5&rate01=300&desc02=UI%2FUX&qty02=2&rate02=250" \
    "${CGI}/invoice")
assert_contains "$body" "INVOICE CREATED" "create returns summary"
assert_contains "$body" "2026-0001" "first invoice numbered 0001"
assert_contains "$body" "2,000.00 EUR" "HT = 2,000.00 (5*300 + 2*250)"
assert_contains "$body" "400.00 EUR"   "TVA 20% = 400.00"
assert_contains "$body" "2,400.00 EUR" "TTC = 2,400.00"
assert_contains "$body" "440.00 EUR"   "URSSAF 22% = 440.00"
assert_contains "$body" "1,560.00 EUR" "Net = 1,560.00"

step "Decimal arithmetic edge case (3 x 33.33 = 99.99)"
body=$(curl -sS -X POST -d \
    "action=create&client_id=CLI-000001&date=2026-05-02&due_date=2026-06-01&tva_rate=0.055&desc01=Book&qty01=3&rate01=33.33" \
    "${CGI}/invoice")
assert_contains "$body" "99.99 EUR"  "3 x 33.33 = 99.99 exact"
assert_contains "$body" "5.50 EUR"   "VAT 5.5% on 99.99 = 5.50 (rounded)"
assert_contains "$body" "105.49 EUR" "TTC = 105.49"

step "PDF generation"
http_code=$(curl -sS -o /dev/null -w '%{http_code}' \
    "${CGI}/pdf-gen?number=2026-0001")
assert_status "$http_code" "302" "pdf-gen returns 302 redirect"

http_code=$(curl -sS -L -o /tmp/cobill-smoke.pdf -w '%{http_code}' \
    "${CGI}/pdf-gen?number=2026-0001")
assert_status "$http_code" "200" "redirect resolves to served PDF"

magic=$(head -c 4 /tmp/cobill-smoke.pdf | xxd -p)
[[ "$magic" == "25504446" ]] \
    && pass "downloaded file has %PDF magic header" \
    || fail "PDF magic header" "got bytes: $magic"

step "Status workflow"
body=$(curl -sS -X POST "${CGI}/invoice?action=mark-paid&number=2026-0001")
assert_contains "$body" "badge-paid" "mark-paid renders PAID badge"

body=$(curl -sS "${CGI}/invoice?action=get&number=2026-0001")
assert_contains "$body" "Paid on"  "detail view shows paid date label"
assert_contains "$body" "REOPEN"   "PAID invoice offers REOPEN button"

step "Auto-OVERDUE detection"
curl -sS -X POST -d \
    "action=create&client_id=CLI-000001&date=2026-04-01&due_date=2026-04-15&tva_rate=0.20&desc01=Late&qty01=1&rate01=500" \
    "${CGI}/invoice" >/dev/null
curl -sS -X POST "${CGI}/invoice?action=mark-sent&number=2026-0003" >/dev/null
body=$(curl -sS "${CGI}/invoice?action=list")
assert_contains "$body" "badge-overdue" "list flags 2026-0003 as OVERDUE"

step "Client soft delete"
curl -sS -X POST "${CGI}/client?action=delete&id=CLI-000001" >/dev/null
body=$(curl -sS "${CGI}/client?action=list")
assert_contains    "$body" "0000 client(s)" "deleted client hidden from list"
assert_not_contains "$body" "Smoke SARL" "name no longer in list"

printf "\n\033[1;32mAll smoke checks passed.\033[0m\n"
