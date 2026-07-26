#!/usr/bin/env bash
# Reject mutable GitHub Action refs and mutable Docker base-image tags.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
errors: list[str] = []

for workflow in sorted((root / ".github" / "workflows").glob("*.y*ml")):
    for line_number, line in enumerate(workflow.read_text(encoding="utf-8").splitlines(), 1):
        match = re.search(r"\buses:\s*([^\s#]+)", line)
        if not match:
            continue
        reference = match.group(1)
        if reference.startswith("./"):
            continue
        if "@" not in reference or not re.fullmatch(r"[0-9a-f]{40}", reference.rsplit("@", 1)[1]):
            errors.append(f"{workflow.relative_to(root)}:{line_number}: mutable action ref {reference}")

dockerfile = root / "Dockerfile"
for line_number, line in enumerate(dockerfile.read_text(encoding="utf-8").splitlines(), 1):
    match = re.match(r"\s*FROM\s+(?:--platform=\S+\s+)?(\S+)", line, re.IGNORECASE)
    if not match or match.group(1).lower() == "scratch":
        continue
    image = match.group(1)
    if not re.search(r"@sha256:[0-9a-f]{64}$", image):
        errors.append(f"Dockerfile:{line_number}: mutable base image {image}")

if errors:
    print("Immutable-reference policy failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: GitHub Actions and Docker base images use immutable references")
PY
