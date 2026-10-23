"""Dev helper: repeatedly parse-check GDScript files and relax `:=` declarations
whose right-hand side is Variant-typed. Stops on any other kind of error."""
import re, subprocess, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
files = sys.argv[1:] or [str(p.relative_to(root)) for p in sorted(root.glob('src/**/*.gd'))] + [str(p.relative_to(root)) for p in sorted(root.glob('tests/*.gd'))]
pat = re.compile(r'at: GDScript::reload \(res://(.+?):(\d+)\)')
fixed = 0
for f in files:
    for _ in range(400):
        out = subprocess.run(['godot', '--headless', '--path', str(root), '--check-only', '--script', 'res://' + f],
                             capture_output=True, text=True).stderr + subprocess.run(['true']).__class__.__name__
        m = pat.search(out)
        if not m:
            break
        msg = out[out.find('SCRIPT ERROR'):].split('\n')[0]
        path, line = m.group(1), int(m.group(2))
        src = (root / path).read_text().split('\n')
        l = src[line - 1]
        if 'Cannot infer the type' in msg and ':=' in l:
            src[line - 1] = l.replace(':=', '=', 1)
            (root / path).write_text('\n'.join(src))
            fixed += 1
            continue
        print(f'{path}:{line}: {msg}\n    {l.strip()}')
        break
print('relaxed', fixed)
