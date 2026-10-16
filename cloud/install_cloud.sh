#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ="$ROOT/requirements/CODEX_FINAL_1001_DEPENDENCIES.txt"
EXC="$ROOT/cloud/PLATFORM_EXCLUSIONS.txt"
LOGDIR="${CODEX_MAGI_LOGDIR:-$ROOT/.install-logs}"
TIMEOUT_SECONDS="${CODEX_MAGI_PACKAGE_TIMEOUT:-1200}"
PYTHON_BIN="${PYTHON_BIN:-python}"

mkdir -p "$LOGDIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="$LOGDIR/cloud_install_report_$STAMP.txt"
FAILED="$LOGDIR/cloud_install_failed_$STAMP.txt"
SKIPPED="$LOGDIR/cloud_install_skipped_$STAMP.txt"
INSTALLED="$LOGDIR/cloud_install_installed_$STAMP.txt"
ALREADY="$LOGDIR/cloud_install_already_$STAMP.txt"

: > "$FAILED"; : > "$SKIPPED"; : > "$INSTALLED"; : > "$ALREADY"

if [[ ! -f "$REQ" ]]; then
  echo "Missing requirements file: $REQ" >&2
  exit 2
fi

normalize() {
  echo "$1" | sed 's/[._-]/-/g' | tr '[:upper:]' '[:lower:]'
}

is_excluded() {
  local pkg_norm
  pkg_norm="$(normalize "$1")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    [[ "$(normalize "$line")" == "$pkg_norm" ]] && return 0
  done < "$EXC"
  return 1
}

is_installed() {
  "$PYTHON_BIN" - "$1" <<'PY'
import importlib.metadata as m, sys
try:
    m.version(sys.argv[1])
    raise SystemExit(0)
except m.PackageNotFoundError:
    raise SystemExit(1)
PY
}

count=0; have=0; installed=0; failed=0; skipped=0
while IFS= read -r pkg || [[ -n "$pkg" ]]; do
  [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
  count=$((count+1))

  if is_excluded "$pkg"; then
    echo "[$count/1001] SKIP platform: $pkg"
    echo "$pkg" >> "$SKIPPED"
    skipped=$((skipped+1))
    continue
  fi

  if is_installed "$pkg"; then
    echo "[$count/1001] HAVE: $pkg"
    echo "$pkg" >> "$ALREADY"
    have=$((have+1))
    continue
  fi

  echo "[$count/1001] INSTALL: $pkg"
  safe="${pkg//[^A-Za-z0-9_.-]/_}"
  if timeout "$TIMEOUT_SECONDS" "$PYTHON_BIN" -m pip install --prefer-binary "$pkg" >"$LOGDIR/${safe}_$STAMP.log" 2>&1; then
    echo "$pkg" >> "$INSTALLED"
    installed=$((installed+1))
  else
    rc=$?
    printf '%s\tEXIT=%s\n' "$pkg" "$rc" >> "$FAILED"
    failed=$((failed+1))
  fi
done < "$REQ"

pip_check="$($PYTHON_BIN -m pip check 2>&1)"; pip_check_rc=$?
cat > "$REPORT" <<EOF2
CODEX / MAGI CLOUD INSTALL REPORT
=================================
Date: $(date -Is)
Python: $($PYTHON_BIN --version 2>&1)
Explicit master targets: 1001
Processed: $count
Already installed: $have
Installed this run: $installed
Platform skipped: $skipped
Failed: $failed

PIP CHECK (exit $pip_check_rc)
-----------------------------
$pip_check

FILES
-----
Already:   $ALREADY
Installed: $INSTALLED
Skipped:   $SKIPPED
Failed:    $FAILED
EOF2

cat "$REPORT"
