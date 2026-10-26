"""Runs the specs in tests/ with the Luau CLI, without Studio.

Run: python3 scripts/run_specs.py [--root FOLDER] [SpecName ...]
(all specs when none are named; --root tests another checkout's scripts)
Needs `luau` on PATH (brew install luau, or the luau-lang/luau releases).
Every script under src/ is placed where Rojo puts it in Studio
(default.project.json), as are the project's plain instances such as the
RemoteEvents in ReplicatedStorage.Remotes, bundled with each spec and
tests/local/harness.luau (Roblox stand-ins: instances, services, vectors,
CFrames, colours, enums and a task scheduler on a virtual clock), and run.
Each spec gets a fresh stand-in world. Exit code 1 if any spec fails.

The stand-ins are lenient (unknown properties read as nil) and have almost
no physics (raycasts hit nothing; box queries compare bounding boxes), so a
pass here is a quick check and Studio stays the final word: specs listed in
STUDIO_ONLY are skipped with the reason.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]

# Specs the stand-ins can't run faithfully, with the reason. Run these in Studio.
STUDIO_ONLY = {}


def long_string(text: str) -> str:
    level = 0
    while ']' + '=' * level + ']' in text:
        level += 1
    eq = '=' * level
    # A newline right after the opening bracket is dropped, so the text stays exact.
    return f'[{eq}[\n{text}]{eq}]'


def script_entry(file: Path, parent: list[str]) -> tuple[list[str], str]:
    name = file.name[:-len('.luau')]
    if name.endswith('.server'):
        return parent + [name[:-len('.server')]], 'Script'
    if name.endswith('.client'):
        return parent + [name[:-len('.client')]], 'LocalScript'
    return parent + [name], 'ModuleScript'


def map_dir(directory: Path, path: list[str], entries: list):
    init = directory / 'init.luau'
    entries.append((path, 'ModuleScript' if init.exists() else 'Folder', init if init.exists() else None))
    for child in sorted(directory.iterdir()):
        if child.is_dir():
            map_dir(child, path + [child.name], entries)
        elif child.suffix == '.luau' and child.name != 'init.luau':
            inst_path, class_name = script_entry(child, path)
            entries.append((inst_path, class_name, child))


def walk(node: dict, path: list[str], entries: list):
    for key, child in node.items():
        if key.startswith('$') or not isinstance(child, dict):
            continue
        child_path = path + [key]
        if '$path' in child:
            map_dir(root / child['$path'], child_path, entries)
        elif '$className' in child:
            entries.append((child_path, child['$className'], None))
        walk(child, child_path, entries)


def bundle(spec: Path, harness: str, entries: list) -> str:
    lines = ['local BUNDLE = { spec = ' + json.dumps(spec.name[:-len('.spec.luau')]) + ', specSource = '
             + long_string(spec.read_text()) + ', tree = {']
    for path, class_name, file in entries:
        source = long_string(file.read_text()) if file else 'nil'
        lines.append(f'\t{{ path = {json.dumps("/".join(path))}, class = "{class_name}", source = {source} }},')
    lines.append('} }')
    return '\n'.join(lines) + '\n' + harness


def main():
    global root
    args = sys.argv[1:]
    if args[:1] == ['--root']:
        root = Path(args[1]).resolve()
        args = args[2:]
    project = json.loads((root / 'default.project.json').read_text())
    entries = []
    walk(project['tree'], [], entries)
    harness = (Path(__file__).resolve().parents[1] / 'tests/local/harness.luau').read_text()
    wanted = set(args)
    specs = sorted(root.glob('tests/*.spec.luau'))
    if wanted:
        specs = [s for s in specs if s.name[:-len('.spec.luau')] in wanted]
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for spec in specs:
            name = spec.name[:-len('.spec.luau')]
            if name in STUDIO_ONLY and not wanted:
                print(f'SKIP {name}: Studio only ({STUDIO_ONLY[name]})')
                continue
            runner = Path(tmp) / f'{name}.luau'
            runner.write_text(bundle(spec, harness, entries))
            try:
                result = subprocess.run(['luau', str(runner)], capture_output=True, text=True, timeout=120)
                output = (result.stdout + result.stderr).strip()
                ok = result.returncode == 0 and output.startswith('PASS')
            except subprocess.TimeoutExpired:
                output, ok = f'FAIL {name}: took over 120s', False
            if not ok:
                failed += 1
                if not output.startswith('FAIL'):
                    output = f'FAIL {name}: ' + output
            print(output)
    print(f'{len(specs) - failed} passed, {failed} failed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
