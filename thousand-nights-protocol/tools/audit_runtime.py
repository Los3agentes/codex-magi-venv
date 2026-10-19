#!/usr/bin/env python3
"""Dependency and graph audit, using only the target Python standard library."""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata as md
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone


def normalize(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def manifest_names(path: Path | None) -> list[str]:
    if path is None:
        return []
    names = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", line)
            if not match:
                raise ValueError(f"Cannot parse distribution name: {line}")
            names.append(match.group(1))
    return names


def inventory() -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {}
    for dist in md.distributions():
        name = dist.metadata.get("Name")
        if not name:
            continue
        key = normalize(name)
        found[key] = {
            "name": name,
            "version": dist.version,
            "requires": list(dist.requires or []),
        }
    return found


def export(phase: str, out_dir: Path, manifest: Path | None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    distributions = inventory()
    expected = manifest_names(manifest)
    targets = [
        {"target": target, "status": "HAVE" if normalize(target) in distributions else "MISSING",
         "installed_version": distributions.get(normalize(target), {}).get("version")}
        for target in expected
    ]
    report = {
        "protocol": "Thousand Nights Protocol",
        "phase": phase,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "python_executable": sys.executable,
        "manifest_entries": len(expected),
        "target_have": sum(t["status"] == "HAVE" for t in targets),
        "target_missing": sum(t["status"] == "MISSING" for t in targets),
        "installed_distribution_count": len(distributions),
        "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest() if manifest else None,
        "targets": targets,
        "distributions": sorted(distributions.values(), key=lambda x: x["name"].casefold()),
    }
    (out_dir / f"audit_{phase}.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    with (out_dir / f"targets_{phase}.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["target", "status", "installed_version"])
        writer.writeheader()
        writer.writerows(targets)
    with (out_dir / f"distributions_{phase}.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "version"])
        writer.writeheader()
        writer.writerows(({"name": d["name"], "version": d["version"]} for d in distributions.values()))
    if phase == "after":
        with (out_dir / "dependency_edges.csv").open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["distribution", "version", "requires_expression"])
            for dist in distributions.values():
                for req in dist["requires"]:
                    writer.writerow([dist["name"], dist["version"], req])
        baseline = out_dir / "audit_before.json"
        if baseline.exists():
            before = json.loads(baseline.read_text(encoding="utf-8"))
            prior = {normalize(d["name"]): d["version"] for d in before.get("distributions", [])}
            current = {normalize(d["name"]): d["version"] for d in distributions.values()}
            summary = {
                "preexisting_distributions": len(prior),
                "after_distributions": len(current),
                "newly_installed": [d["name"] for d in distributions.values() if normalize(d["name"]) not in prior],
                "updated": [d["name"] for d in distributions.values() if normalize(d["name"]) in prior and prior[normalize(d["name"])] != d["version"]],
                "removed": sorted(set(prior) - set(current)),
            }
            (out_dir / "changes.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"{phase}: installed={len(distributions)} targets_have={report['target_have']} targets_missing={report['target_missing']}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", required=True, choices=["before", "after"])
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    a = parser.parse_args()
    export(a.phase, a.out_dir, a.manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
