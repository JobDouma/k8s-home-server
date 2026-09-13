#!/usr/bin/env python3
"""
Usage:
    python3 update_digests.py

Finds all container images in Kubernetes YAML files and pinned shell variables,
and adds SHA256 digests where missing. Uses Docker to resolve digests.

- Skips kustomization.yaml, helmrepository.yaml, and *.sops.* files
- Shell targets are explicitly listed in SHELL_IMAGE_TARGETS below

Run from the root of your git repository. Review with `git diff`, then commit.
"""

import re
import subprocess
import sys
from pathlib import Path

import yaml


# (relative_path, shell_variable_name) pairs to scan for image refs
SHELL_IMAGE_TARGETS = [
    (".githooks/pre-commit", "GITLEAKS_IMAGE"),
]

# YAML filenames/paths to skip entirely
YAML_SKIP_PATTERNS = (".sops", "kustomization.yaml", "helmrepository.yaml")


# ---------------------------------------------------------------------------
# Digest resolution
# ---------------------------------------------------------------------------


def get_digest(image_ref: str, cache: dict[str, str | None]) -> str | None:
    """
    Return the full image reference with SHA256 digest, or None if it already
    has one, contains a shell variable, or cannot be resolved.

    Example: "busybox:latest" -> "busybox:latest@sha256:abc123..."
    """
    if "@sha256:" in image_ref:
        return None  # already pinned
    if "$" in image_ref:
        return None  # shell expansion — skip
    if image_ref in cache:
        return cache[image_ref]

    # Split repo/tag (handle registries with ports like registry:5000/foo)
    if "/" in image_ref and ":" in image_ref.rsplit("/", 1)[-1]:
        repo, tag = image_ref.rsplit(":", 1)
    elif "/" not in image_ref and ":" in image_ref:
        repo, tag = image_ref.rsplit(":", 1)
    else:
        repo, tag = image_ref, "latest"

    try:
        subprocess.run(
            ["docker", "pull", "--quiet", f"{repo}:{tag}"],
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"  ⚠️  Failed to pull {repo}:{tag}: {e.stderr.decode().strip()}",
            file=sys.stderr,
        )
        cache[image_ref] = None
        return None

    try:
        result = subprocess.run(
            [
                "docker",
                "image",
                "inspect",
                f"{repo}:{tag}",
                "--format",
                "{{index .RepoDigests 0}}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        full_digest = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"  ⚠️  Failed to inspect {repo}:{tag}: {e.stderr}", file=sys.stderr)
        cache[image_ref] = None
        return None

    if full_digest and "@sha256:" in full_digest:
        pinned = f"{repo}:{tag}@{full_digest.split('@', 1)[1]}"
        cache[image_ref] = pinned
        return pinned

    cache[image_ref] = None
    return None


# ---------------------------------------------------------------------------
# YAML processing
# ---------------------------------------------------------------------------


def process_yaml_file(filepath: Path, cache: dict) -> None:
    print(f"Processing {filepath}")
    try:
        with open(filepath) as f:
            docs = list(yaml.safe_load_all(f))
    except yaml.YAMLError as e:
        print(f"  ⚠️  Skipping (YAML error): {e}", file=sys.stderr)
        return

    modified = False

    def walk(obj):
        nonlocal modified
        if isinstance(obj, dict):
            for k, v in list(obj.items()):
                if k == "image":
                    if isinstance(v, str):
                        new_v = get_digest(v, cache)
                        if new_v and new_v != v:
                            obj[k] = new_v
                            modified = True
                    elif isinstance(v, dict):
                        repo, tag = v.get("repository"), v.get("tag")
                        if repo and isinstance(tag, str) and "@sha256:" not in tag:
                            new_ref = get_digest(f"{repo}:{tag}", cache)
                            if new_ref and "@sha256:" in new_ref:
                                obj[k]["tag"] = f"{tag}@{new_ref.split('@', 1)[1]}"
                                modified = True
                    else:
                        walk(v)
                else:
                    walk(v)
        elif isinstance(obj, list):
            for item in obj:
                walk(item)

    for doc in docs:
        if doc is not None:
            walk(doc)

    if modified:
        with open(filepath, "w") as f:
            yaml.dump_all(docs, f, default_flow_style=False, sort_keys=False)
        print(f"  ✅ Updated {filepath}")
    else:
        print(f"  ℹ️  No changes needed for {filepath}")


# ---------------------------------------------------------------------------
# Shell file processing
# ---------------------------------------------------------------------------


def _build_shell_re(var_name: str) -> re.Pattern:
    """
    Match lines like:
        GITLEAKS_IMAGE="zricethezav/gitleaks:v8.30.1"
        GITLEAKS_IMAGE='zricethezav/gitleaks:v8.30.1'
        GITLEAKS_IMAGE=zricethezav/gitleaks:v8.30.1   # trailing comment OK
    """
    return re.compile(
        rf"^(?P<prefix>[ \t]*{re.escape(var_name)}=)"
        rf'(?P<quote>["\']?)'
        rf'(?P<image>[^"\'\s#]+)'
        rf"(?P=quote)"
        rf"(?P<suffix>[ \t]*(?:#.*)?)$",
        re.MULTILINE,
    )


def process_shell_file(filepath: str, var_name: str, cache: dict) -> None:
    path = Path(filepath)
    if not path.exists():
        return
    print(f"Processing {filepath} ({var_name})")

    text = path.read_text()
    pattern = _build_shell_re(var_name)

    def repl(match: re.Match) -> str:
        image = match.group("image")
        new_image = get_digest(image, cache)
        if not new_image:
            return match.group(0)
        return (
            f"{match.group('prefix')}"
            f"{match.group('quote')}{new_image}{match.group('quote')}"
            f"{match.group('suffix')}"
        )

    new_text = pattern.sub(repl, text)

    if new_text != text:
        path.write_text(new_text)
        print(f"  ✅ Updated {filepath}")
    else:
        print(f"  ℹ️  No changes needed for {filepath}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _iter_yaml_files():
    for ext in ("*.yaml", "*.yml"):
        for path in Path(".").rglob(ext):
            s = str(path)
            if ".git" in s or any(skip in s for skip in YAML_SKIP_PATTERNS):
                continue
            yield path


def main() -> None:
    cache: dict[str, str | None] = {}

    for path in _iter_yaml_files():
        process_yaml_file(path, cache)

    for shell_path, var_name in SHELL_IMAGE_TARGETS:
        process_shell_file(shell_path, var_name, cache)


if __name__ == "__main__":
    main()
