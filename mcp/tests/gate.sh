#!/usr/bin/env bash
# Everything CI runs, in one command. Run this BEFORE pushing, not after.
#
# Written on 2026-08-20 after two pushes went red in a row for avoidable reasons:
#   20e9a57  the off-domain gate was set at <= 6 answered while 8 are answered
#   54f0181  the fix for that, pushed before re-exporting an unrelated doc drift
#
# Both were caught by checks that already existed. The failure was running SOME of
# them, pushing, and finding out from GitHub. The steps below mirror
# .github/workflows/mcp.yaml exactly; if a step is added there, add it here.
#
#   bash mcp/tests/gate.sh
set -u
cd "$(dirname "$0")/.." || exit 1
export PYTHONIOENCODING=utf-8

ok=1
run() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  [pass] %s\n' "$label"
  else
    printf '  [FAIL] %s\n' "$label"
    ok=0
  fi
}

echo "MCP gate - the same steps as .github/workflows/mcp.yaml"
# The tests import sqldba_mcp; if that resolves to a pinned site-packages install
# instead of this tree, every step below tests the WRONG CODE and passes anyway.
# That happened on 2026-08-21: the suite ran green against an install three edits
# behind the working tree. Fix: pip install -e . from mcp/.
run "editable install (tests run the tree)" python -c "
import pathlib, sqldba_mcp
mod = pathlib.Path(sqldba_mcp.__file__).resolve()
tree = pathlib.Path('src').resolve()
assert str(mod).startswith(str(tree)), 'sqldba_mcp imports from %s, not this tree' % mod
"
run "selftest (datasets load)"        python -m sqldba_mcp --selftest
run "unittest discover"               python -m unittest discover -s tests
run "retrieval eval"                  python tests/eval_faq.py
run "real questions + off-domain"     python -m unittest tests.real_questions
run "freshness (datasets vs source)"  python tests/check_freshness.py

echo
if [ "$ok" = 1 ]; then
  echo "ALL GREEN - safe to push"
  exit 0
fi
echo "RED - do not push. Re-run the failing step without the output suppressed to see why."
exit 1
