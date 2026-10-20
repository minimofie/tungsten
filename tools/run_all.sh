#!/bin/bash
# Runs the offline test suites in normal and SHIFT = 58 mode.
# usage: tools/run_all.sh [suite.luau ...]   (from the folder holding Tungsten/ and tests/)
# needs: python3 and the luau CLI on PATH (github.com/luau-lang/luau releases)
ROOT=$(pwd)
TESTS=$ROOT/tests
OUT=$(mktemp -d)
SUITES=${@:-$(cd "$TESTS" && ls test_*.luau)}
fail=0
for s in $SUITES; do
  for mode in normal shift; do
    src=$TESTS/$s
    if [ $mode = shift ]; then (echo "SHIFT = 58"; cat "$TESTS/$s") > "$OUT/shift_$s"; src=$OUT/shift_$s; fi
    python3 "$TESTS/build_test.py" "$ROOT" "$src" "$OUT/run_$s" >/dev/null
    res=$(luau "$OUT/run_$s" 2>&1); code=$?
    printf "%-24s %-6s %s\n" "$s" "$mode" "$(echo "$res" | grep -E "passed" | tail -1)"
    if [ $code -ne 0 ] || echo "$res" | grep -qE "^FAIL|[1-9][0-9]* failed"; then
      fail=1; echo "$res" | grep -E "^FAIL|error" | head -15
    fi
  done
done
rm -rf "$OUT"
exit $fail
