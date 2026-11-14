# shared by the tests/s3 scripts: `. tests/s3/lib.sh; init NAME "$1"` (run from the repo root).
# init sets NAME, BIN (the s3c binary), T (a private temp dir, removed on exit) and Y1 (the 31 Y1 files).
# bad "why" records a failure; finish prints the one final line (PASS NAME | FAIL NAME (why)) and exits 0 | 1.
init() {
  NAME=$1; BIN=$2; WHY=""
  [ -x "$BIN" ] || { echo "FAIL $NAME (no s3c binary: '$BIN')"; exit 1; }
  [ -f s2/names.srs ] || { echo "FAIL $NAME (run from the repo root)"; exit 1; }
  T=$(mktemp -d "${TMPDIR:-/tmp}/s3t.XXXXXX") || { echo "FAIL $NAME (mktemp)"; exit 1; }
  trap 'rm -rf "$T"' EXIT
  Y1=$(bash tests/s3/y1.sh)
}
bad() { WHY="${WHY:+$WHY; }$1"; }
finish() {
  if [ -z "$WHY" ]; then echo "PASS $NAME"; exit 0; fi
  echo "FAIL $NAME ($WHY)"; exit 1
}
