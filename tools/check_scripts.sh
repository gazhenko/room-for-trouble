#!/bin/sh
# Parse-checks every GDScript file; prints only failures.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
fail=0
for f in $(find src tests tools -name '*.gd' | sort); do
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E 'Parse Error|SCRIPT ERROR|Compile Error' | grep -v 'depended scripts' | head -5)
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
