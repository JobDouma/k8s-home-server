#!/usr/bin/env python3
"""
Usage:
    python3 update_digests.py

This script finds all container images in your Kubernetes YAML files
and adds SHA256 digests where missing. It uses Docker to pull and inspect images.

It skips files like kustomization.yaml, helmrepository.yaml, and any .sops.* files.

Run it from the root of your git repository. After it finishes, review the changes
with `git diff`, then commit and push.
"""

import os
import re
import subprocess
import sys
import yaml
from pathlib import Path


def get_digest(image_ref):
    """
    Return the full image reference with SHA256 digest, or None if already has digest.
    Example: "busybox:latest" -> "busybox:latest@sha256:abc123..."
    """
    if "@sha256:" in image_ref:
        return None  # already pinned

    # Split into repo and tag
    if ":" in image_ref:
        repo, tag = image_ref.rsplit(":", 1)
    else:
        repo, tag = image_ref, "latest"

    # Ensure image is present locally
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
        return None

    # Get the first RepoDigest (e.g., "repo:tag@sha256:digest")
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
        if full_digest:
            # Extract the digest part (after '@')
            if "@sha256:" in full_digest:
                digest = full_digest.split("@")[1]
                return f"{repo}:{tag}@{digest}"
            else:
                # Fallback: use Image ID
                result = subprocess.run(
                    [
                        "docker",
                        "image",
                        "inspect",
                        f"{repo}:{tag}",
                        "--format",
                        "{{.ID}}",
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                )
                image_id = result.stdout.strip()
                if image_id:
                    # Image ID is usually sha256:...
                    if image_id.startswith("sha256:"):
                        return f"{repo}:{tag}@{image_id}"
                    else:
                        return f"{repo}:{tag}@sha256:{image_id}"
                else:
                    return None
        else:
            return None
    except subprocess.CalledProcessError as e:
        print(f"  ⚠️  Failed to inspect {repo}:{tag}: {e.stderr}", file=sys.stderr)
        return None


def process_yaml_file(filepath):
    """Process a single YAML file, updating image fields with digests."""
    print(f"Processing {filepath}")
    with open(filepath, "r") as f:
        try:
            docs = list(yaml.safe_load_all(f))
        except yaml.YAMLError as e:
            print(f"  ⚠️  Skipping (YAML error): {e}", file=sys.stderr)
            return

    modified = False
    new_docs = []

    def walk_and_update(obj):
        nonlocal modified
        if isinstance(obj, dict):
            for k, v in list(obj.items()):
                if k == "image":
                    if isinstance(v, str):
                        new_v = get_digest(v)
                        if new_v and new_v != v:
                            obj[k] = new_v
                            modified = True
                    elif isinstance(v, dict):
                        # Handle repository/tag pattern
                        repo = v.get("repository")
                        tag = v.get("tag")
                        if (
                            repo
                            and tag
                            and isinstance(tag, str)
                            and "@sha256:" not in tag
                        ):
                            new_tag = get_digest(f"{repo}:{tag}")
                            if new_tag and "@sha256:" in new_tag:
                                # new_tag is repo:tag@sha256:...
                                # we want to update the tag field to include the digest
                                sha = new_tag.split("@")[1]
                                obj[k]["tag"] = f"{tag}@{sha}"
                                modified = True
                    else:
                        # If it's something else, just recurse
                        walk_and_update(v)
                else:
                    walk_and_update(v)
        elif isinstance(obj, list):
            for item in obj:
                walk_and_update(item)
        # else: ignore scalars

    for doc in docs:
        if doc is not None:
            walk_and_update(doc)
            new_docs.append(doc)

    if modified:
        with open(filepath, "w") as f:
            yaml.dump_all(new_docs, f, default_flow_style=False, sort_keys=False)
        print(f"  ✅ Updated {filepath}")
    else:
        print(f"  ℹ️  No changes needed for {filepath}")


def main():
    # Find all YAML files, excluding certain patterns
    for path in Path(".").rglob("*.yaml"):
        if any(
            x in str(path)
            for x in [".sops", "kustomization.yaml", "helmrepository.yaml"]
        ):
            continue
        if ".git" in str(path):
            continue
        process_yaml_file(path)
    for path in Path(".").rglob("*.yml"):
        if any(
            x in str(path)
            for x in [".sops", "kustomization.yaml", "helmrepository.yaml"]
        ):
            continue
        if ".git" in str(path):
            continue
        process_yaml_file(path)


if __name__ == "__main__":
    main()
