#!/usr/bin/env python3
"""Sync only distributable assistant sources, preserving any replaced destination."""
import argparse, hashlib, json, re, shutil, tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=Path.home()/"Projects/koreaderx/assistant.koplugin")
parser.add_argument("--checkout", type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument("--backup-dir", type=Path, default=Path(tempfile.gettempdir())/"koreaderx-assistant-backups")
args = parser.parse_args()
source = args.source.resolve()
dest = args.checkout.resolve()/"plugins/assistant.koplugin"
files = {}
for path in source.rglob("*"):
    rel = path.relative_to(source)
    top = len(rel.parts) == 1
    allowed = (top and (path.name in {"main.lua", "_meta.lua", "LICENSE", "README.md", "configuration.sample.lua", "configuration.default.lua"}
                       or (path.name.startswith("assistant_") and path.suffix == ".lua"))) or (
                       len(rel.parts) == 2 and rel.parts[0] == "api_handlers" and path.suffix == ".lua") or (
                       len(rel.parts) == 3 and rel.parts[0] == "l10n" and path.suffix == ".po")
    if not allowed or not path.is_file():
        continue
    if path.is_symlink() or not path.resolve().is_relative_to(source):
        raise SystemExit("Refusing symlink: " + str(rel))
    data = path.read_bytes()
    if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16}", data):
        raise SystemExit("Potential credential in distributable file: " + str(rel))
    files[str(rel)] = data
for required in ("main.lua", "_meta.lua", "assistant_paths.lua", "configuration.default.lua", "api_handlers/offline.lua", "LICENSE"):
    if required not in files: raise SystemExit("Missing required runtime file: " + required)
old = {str(p.relative_to(dest)):p.read_bytes() for p in dest.rglob("*") if p.is_file()} if dest.exists() else {}
if old != files:
    if dest.exists():
        args.backup_dir.mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix="assistant-", dir=args.backup_dir))
        shutil.copytree(dest, backup/"assistant.koplugin", symlinks=True)
        print("Previous destination preserved at", backup)
        shutil.rmtree(dest)
    for rel, data in files.items():
        path = dest/rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
manifest = {name:hashlib.sha256(data).hexdigest() for name,data in sorted(files.items())}
(args.checkout/"tools/koreaderx/assistant-files.json").write_text(json.dumps(manifest, indent=2)+"\n")
print("Synchronized", len(files), "files; configuration.lua and development files excluded")
