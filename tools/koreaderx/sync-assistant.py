#!/usr/bin/env python3
"""Validate the vendored assistant snapshot, or explicitly sync distributable sources."""
import argparse, hashlib, json, re, shutil, tempfile
from pathlib import Path


def allowed(rel):
    top = len(rel.parts) == 1
    return (top and (rel.name in {"main.lua", "_meta.lua", "LICENSE", "README.md", "configuration.sample.lua", "configuration.default.lua"}
                    or (rel.name.startswith("assistant_") and rel.suffix == ".lua"))) or (
                    len(rel.parts) == 2 and rel.parts[0] == "api_handlers" and rel.suffix == ".lua") or (
                    len(rel.parts) == 3 and rel.parts[0] == "l10n" and rel.suffix == ".po")


def read_sources(source, strict):
    if not source.is_dir():
        raise SystemExit("Missing assistant directory: " + str(source))
    files = {}
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        if path.is_symlink():
            if strict or allowed(rel) or rel.parts[0] in {"api_handlers", "l10n"}:
                raise SystemExit("Refusing symlink: " + str(rel))
            continue
        if not path.is_file():
            continue
        if not allowed(rel):
            if strict:
                raise SystemExit("Unexpected file in packaged assistant: " + str(rel))
            # Never read personal configuration.lua, development files or caches.
            continue
        data = path.read_bytes()
        if re.search(rb"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16}|AIza[A-Za-z0-9_-]{35}", data):
            raise SystemExit("Potential credential in distributable file: " + str(rel))
        # Catch unprefixed provider keys in literal Lua assignments as well. Only
        # placeholders (or Ollama's documented non-secret sentinel) may ship.
        for match in re.finditer(rb"\bapi_key\s*=\s*([\"'])([^\"'\r\n]*)\1", data):
            key = match[2]
            if key not in (b"", b"ollama") and not re.fullmatch(rb"your-[a-z0-9_-]+", key):
                raise SystemExit("Non-placeholder API key in distributable file: " + str(rel))
        files[str(rel)] = data
    for required in ("main.lua", "_meta.lua", "assistant_paths.lua", "assistant_transport.lua",
                     "configuration.default.lua", "api_handlers/offline.lua", "LICENSE"):
        if required not in files:
            raise SystemExit("Missing required runtime file: " + required)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--source", type=Path, help="Explicit development source to sync; omitted: validate only")
    mode.add_argument("--check", action="store_true", help="Validate the vendored files and manifest without changes (default)")
    parser.add_argument("--checkout", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--backup-dir", type=Path, default=Path(tempfile.gettempdir())/"koreaderx-assistant-backups")
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    dest = checkout/"plugins/assistant.koplugin"
    if dest.is_symlink():
        raise SystemExit("Refusing symlink destination")
    source = args.source.resolve() if args.source else dest
    files = read_sources(source, strict=args.source is None)
    manifest = {name:hashlib.sha256(data).hexdigest() for name,data in sorted(files.items())}
    manifest_path = checkout/"tools/koreaderx/assistant-files.json"
    if args.source is None:
        try:
            expected = json.loads(manifest_path.read_text())
        except (OSError, ValueError) as exc:
            raise SystemExit("Cannot read assistant manifest: " + str(exc))
        if expected != manifest:
            raise SystemExit("Vendored assistant differs from assistant-files.json; restore the snapshot or explicitly sync and review the changes")
        print("Validated", len(files), "vendored files; no external source used, no files changed")
        return
    if source == dest or source.is_relative_to(dest) or dest.is_relative_to(source):
        raise SystemExit("Source and destination must be separate; use --check for the vendored snapshot")
    # Compare names first, without reading any unexpected private configuration.
    old_paths = {str(p.relative_to(dest)):p for p in dest.rglob("*") if p.is_file() or p.is_symlink()} if dest.exists() else {}
    same = set(old_paths) == set(files) and all(not old_paths[name].is_symlink() and old_paths[name].read_bytes() == data for name,data in files.items())
    if not same:
        if dest.exists():
            args.backup_dir.mkdir(parents=True, exist_ok=True)
            backup = Path(tempfile.mkdtemp(prefix="assistant-", dir=args.backup_dir))
            shutil.copytree(dest, backup/"assistant.koplugin", symlinks=True)
            print("Previous destination preserved at", backup)
            shutil.rmtree(dest)
        for rel, data in files.items():
            path = dest/rel; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    manifest_path.write_text(json.dumps(manifest, indent=2)+"\n")
    print("Synchronized", len(files), "files; configuration.lua and development files excluded")


if __name__ == "__main__":
    main()
