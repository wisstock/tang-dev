#!/bin/bash
# Check the installed toolchain against tools.lock; extract the archive if .tools/ is missing.
# Usage: scripts/check_tools.sh <tools.lock> <downloads dir> <oss-cad-suite dir>
# No network and no board access. Exit 1 on any mismatch.
set -u
LOCK=$1 DL=$2 OSS=$3
fail=0

# Value of "key = value" in tools.lock (spaces around '=' ignored)
get() { awk -F' *= *' -v k="$1" '$1 == k { print $2; exit }' "$LOCK"; }
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

archive=$(get archive)
[ -n "$archive" ] || { echo "No 'archive' in $LOCK"; exit 1; }
echo "tools.lock: $archive"

# 1. Archive hash (optional if the tools are already installed)
if [ -f "$DL/$archive" ]; then
    got=$(shasum -a 256 "$DL/$archive" | cut -d' ' -f1)
    if [ "$got" = "$(get sha256)" ]; then ok "archive SHA-256"; else bad "archive SHA-256: $got"; fi
elif [ -d "$OSS" ]; then
    echo "  SKIP  archive not in $DL (installed tools are still checked)"
else
    echo "  FAIL  neither $DL/$archive nor $OSS exists: download the archive (README.md, Setup)"
    exit 1
fi

# 2. Extract when the tools are missing and the archive is verified
if [ ! -d "$OSS" ]; then
    [ "$fail" = 0 ] || { echo "Not extracting: archive hash mismatch"; exit 1; }
    echo "  ...   extracting into $(dirname "$OSS")"
    mkdir -p "$(dirname "$OSS")" && tar -xzf "$DL/$archive" -C "$(dirname "$OSS")" \
        && ok "extracted" || { bad "extraction"; exit 1; }
fi

# 3. Version strings printed by the tools must contain the value from tools.lock.
# Tools may print "Operation not permitted" for ~/.config inside the sandbox: output is merged and searched.
check() {  # check <lock key> <command...>
    local key=$1; shift
    local want; want=$(get "$key")
    if "$@" 2>&1 | grep -qF -- "$want"; then ok "$key: $want"; else bad "$key: expected '$want'"; fi
}
B=$OSS/bin
check yosys              "$B/yosys" -V
check nextpnr-himbaechel "$B/nextpnr-himbaechel" --version
check verilator          "$B/verilator" --version
check iverilog           "$B/iverilog" -V
check cocotb             "$B/cocotb-config" --version

# apycula (gowin_pack) has no version flag: check its installed package metadata
want=$(get apycula)
if ls -d "$OSS"/lib/python3*/site-packages/apycula-"$want".dist-info >/dev/null 2>&1; then ok "apycula: $want"; else bad "apycula: expected '$want'"; fi

# Not executed on purpose (AGENTS.md rule 7: board tools only via their own targets): presence only
if [ -x "$B/openFPGALoader" ]; then ok "openFPGALoader present (version $(get openFPGALoader) not executed)"; else bad "openFPGALoader missing"; fi

# Gowin GW1N-9C support files used by the build
for f in share/nextpnr/himbaechel/gowin/chipdb-GW1N-9C.bin bin/gowin_pack; do
    if [ -e "$OSS/$f" ]; then ok "$f"; else bad "$f missing"; fi
done

[ "$fail" = 0 ] && echo "check-tools: OK" || echo "check-tools: FAILED"
exit $fail
