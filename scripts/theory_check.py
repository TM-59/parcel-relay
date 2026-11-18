"""Check docs/theory against the code. Run with `make theory-check`. Standard library only.

Every statement has a page section and a figure, every link and figure exists, every referenced
function / test token is still in the source, and every exported function is listed.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THEORY = ROOT / "docs/theory"
FIGS = "scripts/theory_figs.exs"
ROW = re.compile(r"\| (S\d\d) \| (.+?) \| \[\d\]\(([^)]+)\) \| (.+?) \| (.+?) \| (.+?) \|$")
PARTS = ("Statement.", "Assumptions", "Derivation.", "Code.", "Tests.")
NOT_VALUES = ("stateDiagram-v2",)  # Mermaid keywords that look like measured-value ids


def refs(cell: str) -> list[tuple[str, str]]:
    """Return the `file#token` references written in one table cell."""
    return re.findall(r"`([^`#\s]+)#([^`\n]+)`", cell)


def table_rows(index: str, errors: list[str]) -> dict[str, dict[str, str]]:
    """Read the coverage table of the index and check the README statement count."""
    rows: dict[str, dict[str, str]] = {}
    for line in index.splitlines():
        found = ROW.match(line)
        if found:
            rows[found.group(1)] = {
                "page": found.group(3),
                "figure": found.group(4),
                "code": found.group(5),
                "test": found.group(6),
            }
    if not rows:
        errors.append("coverage table not found in docs/theory/README.md")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    count = re.search(r"— (\d+) statements", readme)
    if not count or int(count.group(1)) != len(rows):
        errors.append("README statement count does not match the coverage table")
    return rows


def page_sections(pages: dict[str, str]) -> dict[str, tuple[str, str]]:
    """Return each statement's page and section body."""
    sections: dict[str, tuple[str, str]] = {}
    for name, text in pages.items():
        for head in re.finditer(r"^## (S\d\d) — .*$", text, flags=re.MULTILINE):
            end = text.find("\n## ", head.end())
            sections[head.group(1)] = (name, text[head.end() : end if end > 0 else len(text)])
    return sections


def figure_errors(sid: str, body: str, row: dict[str, str]) -> list[str]:
    """Check that the section shows a figure and every figure the table lists."""
    errors: list[str] = []
    images = re.findall(r"!\[[^\]]*\]\(([^)]+)\)", body)
    has_mermaid = "```mermaid" in body
    if not images and not has_mermaid:
        errors.append(f"{sid}: no figure (neither an image nor a mermaid diagram)")
    errors.extend(
        f"{sid}: figure {image} does not exist (run make theory-figs)"
        for image in images
        if not (THEORY / image).is_file()
    )
    if "mermaid" in row["figure"] and not has_mermaid:
        errors.append(f"{sid}: table says mermaid, section has none")
    errors.extend(
        f"{sid}: table lists {figure}, the section does not show it"
        for figure in re.findall(r"`(figures/[^`]+)`", row["figure"])
        if figure not in images
    )
    return errors


def reference_errors(sid: str, row: dict[str, str], values: str) -> list[str]:
    """Check that every code and test reference still exists."""
    errors: list[str] = []
    for cell in (row["code"], row["test"]):
        if not refs(cell):
            errors.append(f"{sid}: a code/test cell has no `file#token` reference")
        for file, token in refs(cell):
            path = ROOT / file
            if not path.is_file():
                errors.append(f"{sid}: {file} does not exist")
            elif file == FIGS:
                if (
                    f'"{token}"' not in path.read_text(encoding="utf-8")
                    or f"`{token}`" not in values
                ):
                    errors.append(
                        f"{sid}: measured value {token} is not produced by {FIGS} / values.md"
                    )
            elif token not in path.read_text(encoding="utf-8"):
                errors.append(f"{sid}: {token} is no longer in {file}")
    return errors


def statement_errors(
    rows: dict[str, dict[str, str]], sections: dict[str, tuple[str, str]], values: str
) -> list[str]:
    """Check each statement: table row, section, figure, part order and references."""
    errors: list[str] = []
    for sid in sorted(set(rows) | set(sections)):
        if sid not in rows:
            errors.append(f"{sid}: section exists but is missing from the coverage table")
            continue
        if sid not in sections:
            errors.append(f"{sid}: in the coverage table but has no section")
            continue
        name, body = sections[sid]
        row = rows[sid]
        if row["page"] != name:
            errors.append(f"{sid}: table says {row['page']}, section is in {name}")
        errors.extend(figure_errors(sid, body, row))
        positions = [body.find(f"**{part}") for part in PARTS]
        if min(positions) < 0 or positions != sorted(positions):
            errors.append(
                f"{sid}: needs Statement, Assumptions, Derivation, Code, Tests in this order"
            )
        errors.extend(reference_errors(sid, row, values))
    return errors


def page_errors(pages: dict[str, str], index: str, values: str) -> list[str]:
    """Check quoted measured-value ids and the links between Markdown files."""
    errors: list[str] = []
    for name, text in pages.items():
        for token in re.findall(r"\(`([a-z0-9.-]+)`\)|`([a-z]+-[a-z0-9.-]+)`", text):
            key = token[0] or token[1]
            quoted = re.fullmatch(r"[a-z]+(-[a-z0-9.]+)+", key) and "/" not in key
            if quoted and f"`{key}`" not in values and not key.startswith("make"):
                if key in NOT_VALUES:
                    continue
                errors.append(f"{name}: quotes value `{key}` that figures/values.md does not have")
    errors.extend(
        f"{name}: broken link {target}"
        for name, text in {**pages, "README.md": index}.items()
        for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", text)
        if "://" not in target and not (THEORY / target).exists()
    )
    return errors


def export_errors(mentioned: set[str]) -> list[str]:
    """Check that every public function of lib/*.ex is in one of the index tables."""
    errors: list[str] = []
    for source in sorted((ROOT / "lib").glob("*.ex")):
        text = source.read_text(encoding="utf-8")
        exported = sorted(set(re.findall(r"^  def ([a-z_]+)", text, flags=re.MULTILINE)))
        errors.extend(
            f"{source.name}: public function {fn} is in neither table of docs/theory/README.md"
            for fn in exported
            if fn not in mentioned
        )
    return errors


def main() -> int:
    """Run every check and print the result."""
    index = (THEORY / "README.md").read_text(encoding="utf-8")
    pages = {p.name: p.read_text(encoding="utf-8") for p in sorted(THEORY.glob("0*.md"))}
    values_path = THEORY / "figures/values.md"
    values = values_path.read_text(encoding="utf-8") if values_path.exists() else ""
    errors: list[str] = []
    rows = table_rows(index, errors)
    errors.extend(statement_errors(rows, page_sections(pages), values))
    errors.extend(page_errors(pages, index, values))
    mentioned = {token.rstrip("(") for _, token in refs(index)}
    errors.extend(export_errors(mentioned))
    if errors:
        sys.stdout.write("\n".join(errors) + "\n")
        sys.stdout.write(f"theory-check: {len(errors)} problem(s)\n")
        return 1
    figures = sum(1 for _ in THEORY.glob("figures/*.svg"))
    sys.stdout.write(
        f"theory-check: OK ({len(rows)} statements, each with a figure; {figures} generated "
        f"figures; {len(mentioned)} functions/tests/values referenced)\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
