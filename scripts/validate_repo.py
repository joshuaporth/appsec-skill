#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
LINK_RE = re.compile(r"(?<!\!)\[[^\]]+\]\(([^)]+)\)")
FENCED_BLOCK_RE = re.compile(r"```.*?```", re.DOTALL)
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):(?:\s|$)")


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_frontmatter(path: Path, failures: list[str]) -> dict[str, str]:
    content = read_text(path)
    match = FRONTMATTER_RE.match(content)
    if not match:
        fail(f"{path.relative_to(REPO_ROOT)}: missing YAML frontmatter", failures)
        return {}

    keys: dict[str, str] = {}
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue
        key_match = KEY_RE.match(line)
        if key_match:
            key = key_match.group(1)
            value = line.split(":", 1)[1].strip()
            keys[key] = value
    return keys


def validate_frontmatter(failures: list[str]) -> None:
    for path in sorted(REPO_ROOT.rglob("SKILL.md")):
        if "benchmark/challenges" in path.as_posix():
            continue
        keys = parse_frontmatter(path, failures)
        for required_key in ("name", "description"):
            if required_key not in keys:
                fail(
                    f"{path.relative_to(REPO_ROOT)}: frontmatter missing '{required_key}'",
                    failures,
                )

    root_skill = REPO_ROOT / "skill" / "SKILL.md"
    if root_skill.exists():
        keys = parse_frontmatter(root_skill, failures)
        for required_key in ("version", "spec_version"):
            if required_key not in keys:
                fail(
                    f"skill/SKILL.md: frontmatter missing '{required_key}'",
                    failures,
                )


def validate_skill_reference_chain(failures: list[str]) -> None:
    skill_path = REPO_ROOT / "skill" / "SKILL.md"
    content = read_text(skill_path)
    listed_refs = re.findall(
        r"^\d+\.\s+\[references/[^\]]+\]\((references/[^)]+)\)",
        content,
        flags=re.MULTILINE,
    )
    expected_refs = [
        f"references/{path.name}"
        for path in sorted((REPO_ROOT / "skill" / "references").glob("*.md"))
    ]

    if listed_refs != expected_refs:
        fail(
            "skill/SKILL.md: reference list must match skill/references/*.md in sorted order",
            failures,
        )

    for ref in listed_refs:
        target = skill_path.parent / ref
        if not target.exists():
            fail(f"skill/SKILL.md: linked reference does not exist: {ref}", failures)


def iter_markdown_files() -> list[Path]:
    roots = [
        REPO_ROOT / "README.md",
        REPO_ROOT / "CONTRIBUTING.md",
    ]
    files: set[Path] = {path for path in roots if path.exists()}
    for base in (REPO_ROOT / "skill", REPO_ROOT / ".cursor" / "skills"):
        if not base.exists():
            continue
        for path in base.rglob("*.md"):
            files.add(path)
    return sorted(files)


def validate_markdown_links(failures: list[str]) -> None:
    for path in iter_markdown_files():
        content = FENCED_BLOCK_RE.sub("", read_text(path))
        for raw_target in LINK_RE.findall(content):
            target = raw_target.strip()
            if not target or target.startswith("#"):
                continue
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", target):
                continue
            if target.startswith("mailto:"):
                continue

            location = target.split("#", 1)[0]
            if not location:
                continue

            resolved = (path.parent / location).resolve()
            try:
                resolved.relative_to(REPO_ROOT.resolve())
            except ValueError:
                fail(
                    f"{path.relative_to(REPO_ROOT)}: link escapes repo root: {target}",
                    failures,
                )
                continue

            if not resolved.exists():
                fail(
                    f"{path.relative_to(REPO_ROOT)}: broken local link: {target}",
                    failures,
                )


def main() -> int:
    failures: list[str] = []
    validate_frontmatter(failures)
    validate_skill_reference_chain(failures)
    validate_markdown_links(failures)

    if failures:
        print("Repository validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Repository validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
