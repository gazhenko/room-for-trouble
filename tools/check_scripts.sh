#!/bin/sh
# Parse-checks every GDScript file; prints only failures. Refreshes the class
# cache first so new class_name scripts resolve.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
fail=0
for f in $(find src tests tools -name '*.gd' | sort); do
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -A1 -E 'Parse Error|Compile Error' | grep -v -E "depended scripts|Identifier not found: (Content|Loc|Settings|SaveService|InputRouter|Audio|Net|Session)" | head -4)
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
