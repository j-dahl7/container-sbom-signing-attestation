from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts" / "verify-image.sh"
IMAGE = "ghcr.io/example/supply-chain@sha256:" + "a" * 64
REPOSITORY = "example/supply-chain"
WSL_BASH = os.name == "nt" and subprocess.run(
    ["bash", "-lc", "test -d /mnt/c"], check=False
).returncode == 0


def bash_path(path: Path) -> str:
    value = path.resolve().as_posix()
    if len(value) >= 3 and value[1:3] == ":/":
        prefix = "/mnt/" if WSL_BASH else "/"
        return f"{prefix}{value[0].lower()}{value[2:]}"
    return value


class SupplyChainContractTests(unittest.TestCase):
    def run_verifier(self, failure: str = "") -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            log = temporary / "cosign.log"
            cosign = temporary / "cosign"
            cosign.write_bytes(
                textwrap.dedent(
                    r"""#!/usr/bin/env bash
                    set -eu
                    printf '%s\\n' "$*" >> "$COSIGN_LOG"
                    case "$COSIGN_FAILURE:$*" in
                      signature:verify\ *) exit 1 ;;
                      sbom:verify-attestation\ *--type\ spdxjson*) exit 1 ;;
                      provenance:verify-attestation\ *--type\ slsaprovenance*) exit 1 ;;
                      provenance:verify-attestation\ *--type\ https://slsa.dev/provenance/v1*) exit 1 ;;
                    esac
                    exit 0
                    """
                ).encode("utf-8"),
            )
            cosign.chmod(0o755)
            command = " ".join(
                [
                    f"COSIGN_BIN={shlex.quote(bash_path(cosign))}",
                    f"COSIGN_LOG={shlex.quote(bash_path(log))}",
                    f"COSIGN_FAILURE={shlex.quote(failure)}",
                    shlex.quote(bash_path(VERIFY)),
                    shlex.quote(IMAGE),
                    shlex.quote(REPOSITORY),
                ]
            )
            result = subprocess.run(
                ["bash", "-lc", command],
                text=True,
                capture_output=True,
                check=False,
            )
            result.cosign_log = log.read_text(encoding="utf-8") if log.exists() else ""  # type: ignore[attr-defined]
            return result

    def test_verification_requires_exact_repository_workflow_identity(self) -> None:
        result = self.run_verifier()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = result.cosign_log  # type: ignore[attr-defined]
        self.assertIn(r"example/supply-chain/\.github/workflows/supply-chain", log)
        self.assertIn("heads/main|tags/v", log)
        self.assertNotIn("github.com/.*", log)
        self.assertIn("--type spdxjson", log)
        self.assertRegex(log, r"--type (slsaprovenance|https://slsa.dev/provenance/v1)")

    def test_missing_signature_fails_closed(self) -> None:
        self.assertEqual(self.run_verifier("signature").returncode, 1)

    def test_missing_sbom_fails_closed(self) -> None:
        self.assertEqual(self.run_verifier("sbom").returncode, 1)

    def test_missing_provenance_fails_closed(self) -> None:
        self.assertEqual(self.run_verifier("provenance").returncode, 1)

    def test_incomplete_digest_is_rejected_before_cosign(self) -> None:
        result = subprocess.run(
            ["bash", bash_path(VERIFY), "ghcr.io/example/image@sha256:abc", REPOSITORY],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)

    def test_workflow_has_read_only_default_and_ref_gated_publish(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "supply-chain.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"(?m)^permissions:\n  contents: read$")
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertNotIn("github.event_name != 'pull_request'", workflow)

    def test_all_action_and_base_image_refs_are_immutable(self) -> None:
        result = subprocess.run(
            ["bash", bash_path(ROOT / "scripts" / "check-pinned-refs.sh")],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^FROM .*@sha256:[0-9a-f]{64}", dockerfile)), 2)

    def test_local_build_fails_closed_on_scanning_and_health(self) -> None:
        local_build = (ROOT / "scripts" / "local-build.sh").read_text(encoding="utf-8")
        self.assertIn("trivy image", local_build)
        self.assertIn("--exit-code 1", local_build)
        self.assertIn("curl --fail", local_build)
        self.assertNotIn("Trivy not installed", local_build)


if __name__ == "__main__":
    unittest.main()
