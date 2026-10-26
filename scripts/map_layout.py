"""Writes art/export/props/layout.txt: Brainrot Battlefield as the game
builds it, dressed with every Blender prop, for the map renders in
art/blender/build_props.py. Runs scripts/map_layout.luau on the spec
harness (needs `luau` on PATH, like scripts/run_specs.py).

Run: python3 scripts/map_layout.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_specs  # noqa: E402

root = Path(__file__).resolve().parents[1]


def main():
    project = json.loads((root / 'default.project.json').read_text())
    entries = []
    run_specs.walk(project['tree'], [], entries)
    harness = (root / 'tests/local/harness.luau').read_text()
    script = root / 'scripts/map_layout.luau'
    with tempfile.TemporaryDirectory() as tmp:
        runner = Path(tmp) / 'map_layout.luau'
        runner.write_text(run_specs.bundle(script, harness, entries))
        result = subprocess.run(['luau', str(runner)], capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    if result.returncode != 0 or not output.startswith('PASS'):
        sys.exit('map_layout.luau failed:\n' + output[:4000])
    lines = [line.split('LAYOUT ', 1)[1] for line in output.splitlines() if 'LAYOUT ' in line]
    out = root / 'art/export/props/layout.txt'
    out.write_text('\n'.join(lines) + '\n')
    print(f'{len(lines)} parts -> {out.relative_to(root)}')


if __name__ == '__main__':
    main()
