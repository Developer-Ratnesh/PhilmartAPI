"""Verify the Schedule A controlled baseline (Delivery Plan task T01).

Re-hashes every file listed in the pack's SHA256_MANIFEST.csv and checks the
manifest itself against the digest recorded in BRD section 2.3. This is a full
re-hash, not a spot check: any missing, resized or changed file fails the run.

Usage:
    python tools/verify_baseline.py <path to PHILMART_DEVELOPER_SLIM folder> [--report out.md]
"""

import argparse
import csv
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

MANIFEST_DIGEST = "89e690c665ae88a18db4381b109ab133134e4f2d9354547d9f3d13d4c1569609"
MANIFEST_PATH = Path("99_INTEGRITY_AUDIT") / "SHA256_MANIFEST.csv"
EXPECTED_FILE_COUNT = 238


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def long_path(root: Path) -> Path:
    # Some screen evidence files sit past Windows' 260-character MAX_PATH once
    # the pack is unzipped under a user folder; the \\?\ prefix lifts the limit.
    root = root.resolve()
    if sys.platform == "win32" and not str(root).startswith("\\\\?\\"):
        return Path("\\\\?\\" + str(root))
    return root


def verify(root: Path):
    root = long_path(root)
    manifest = root / MANIFEST_PATH
    problems = []

    manifest_digest = sha256(manifest)
    if manifest_digest != MANIFEST_DIGEST:
        problems.append(f"Manifest digest {manifest_digest} does not match BRD 2.3 digest {MANIFEST_DIGEST}")

    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    if len(rows) != EXPECTED_FILE_COUNT:
        problems.append(f"Manifest lists {len(rows)} files, BRD 2.3 states {EXPECTED_FILE_COUNT}")

    for row in rows:
        relative = row["Relative path"]
        path = root / relative
        if not path.is_file():
            problems.append(f"MISSING  {relative}")
            continue
        size = path.stat().st_size
        if size != int(row["Size bytes"]):
            problems.append(f"SIZE     {relative}: {size} bytes, manifest says {row['Size bytes']}")
        actual = sha256(path)
        if actual != row["SHA256"].lower():
            problems.append(f"HASH     {relative}: {actual}, manifest says {row['SHA256']}")

    listed = {Path(row["Relative path"]).as_posix() for row in rows} | {MANIFEST_PATH.as_posix()}
    unlisted = sorted(
        p.relative_to(root).as_posix()
        for p in root.rglob("*")
        if p.is_file() and p.relative_to(root).as_posix() not in listed
    )

    return manifest_digest, rows, problems, unlisted


def write_report(path: Path, root: Path, manifest_digest, rows, problems, unlisted):
    verdict = "PASS" if not problems else "FAIL"
    lines = [
        "# T01 Schedule A baseline integrity confirmation",
        "",
        f"- Verified at: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"- Pack root: `{root.name}`",
        f"- Manifest: `{MANIFEST_PATH.as_posix()}`",
        f"- Manifest SHA-256: `{manifest_digest}`",
        f"- BRD 2.3 expected: `{MANIFEST_DIGEST}`",
        f"- Files in manifest: {len(rows)} (expected {EXPECTED_FILE_COUNT})",
        f"- Files re-hashed: {len(rows)}",
        f"- Mismatches: {len(problems)}",
        f"- Files present but not in the manifest: {len(unlisted)}",
        "",
        f"**Result: {verdict}**",
        "",
    ]
    if problems:
        lines += ["## Mismatches", ""] + [f"- {p}" for p in problems] + [""]
    if unlisted:
        lines += ["## Not in manifest (informational)", ""] + [f"- `{p}`" for p in unlisted] + [""]
    lines += [
        "## Sign-off",
        "",
        "Verified by: ______________________   Date: ____________",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    manifest_digest, rows, problems, unlisted = verify(args.root)

    for problem in problems:
        print(problem)
    print(f"{len(rows)} files re-hashed, {len(problems)} problems, {len(unlisted)} unlisted files")
    print("PASS" if not problems else "FAIL")

    if args.report:
        write_report(args.report, args.root, manifest_digest, rows, problems, unlisted)

    sys.exit(0 if not problems else 1)


if __name__ == "__main__":
    main()
