"""Structure and safety checks for skills/bitwarden."""
import re
import stat
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent / "skills" / "bitwarden"
SKILL_MD = SKILL / "SKILL.md"
REFS = {
    "secrets-manager": SKILL / "references" / "secrets-manager.md",
    "password-manager": SKILL / "references" / "password-manager.md",
}
WRAPPERS = ["bws-token", "bwsx", "bw-token", "bw-unlock", "bwx", "bw-fill", "bws-audit.sh"]
SHIPPED_TEXT = [p for p in SKILL.rglob("*") if p.is_file()]
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
REPEATED_UUID = re.compile(r"^([0-9a-f])\1{7}-\1{4}-\1{4}-\1{4}-\1{12}$", re.I)


def frontmatter(text):
    lines = text.splitlines()
    assert lines[0] == "---", "SKILL.md must start with YAML frontmatter"
    end = lines.index("---", 1)
    return "\n".join(lines[1:end])


def test_frontmatter_fields():
    fm = frontmatter(SKILL_MD.read_text())
    assert re.search(r"^name: bitwarden$", fm, re.M)
    assert re.search(r"^description: ", fm, re.M)
    assert "allowed-tools:" in fm


def test_router_links_both_references():
    body = SKILL_MD.read_text()
    for path in REFS.values():
        assert path.exists(), path
        assert f"references/{path.name}" in body, f"SKILL.md does not route to {path.name}"


def test_router_stays_product_neutral():
    body = SKILL_MD.read_text()
    for step in ("--project-id", "--folderid", "list items"):
        assert step not in body, f"product-specific step '{step}' belongs in a reference, not SKILL.md"


def test_references_carry_their_rules():
    sm = REFS["secrets-manager"].read_text()
    pm = REFS["password-manager"].read_text()
    for term in ("bwsx", "bws run", "bws secret get", "set -euo pipefail", "--no-inherit-env"):
        assert term in sm, f"secrets-manager.md missing '{term}'"
    for term in ("bw-fill --clear", "--folderid", "bw get password", "weaker than Secrets Manager"):
        assert term in pm, f"password-manager.md missing '{term}'"


def test_wrappers_present_and_executable():
    for name in WRAPPERS:
        path = SKILL / "scripts" / name
        assert path.exists(), path
        assert path.stat().st_mode & stat.S_IXUSR, f"{name} is not executable"
        text = path.read_text()
        assert text.startswith("#!/usr/bin/env bash"), name
        assert "set -euo pipefail" in text, name


def test_example_scripts_follow_the_rules():
    scripts = list((SKILL / "examples").glob("*.sh"))
    assert scripts, "examples/ has no shell example"
    for sh in scripts:
        text = sh.read_text()
        assert sh.stat().st_mode & stat.S_IXUSR, f"{sh.name} is not executable"
        assert "set -euo pipefail" in text, sh.name
        assert ":?" in text, f"{sh.name} must assert its injected variable"
        assert "bws secret get" not in text, sh.name


def test_no_unfiltered_item_listing():
    """`bw list items` prints passwords unless filtered."""
    for path in SHIPPED_TEXT:
        for line in path.read_text().splitlines():
            if re.search(r"\bbwx\s+\S+\s+list items\b", line) and not line.rstrip().endswith("\\"):
                assert "| jq" in line, f"{path.name}: unfiltered item listing: {line.strip()}"


def test_no_personal_or_real_identifiers():
    banned = re.compile(r"\b(mac|forge|ClaudeAgent|davcomm|reidcardwell)\b")
    for path in SHIPPED_TEXT:
        text = path.read_text()
        assert not banned.search(text), f"{path.relative_to(SKILL)} contains a personal literal: {banned.search(text).group()}"
        for match in UUID.finditer(text):
            uuid = match.group()
            assert REPEATED_UUID.match(uuid) or "-0000-0000-0000-" in uuid, (
                f"{path.relative_to(SKILL)} contains a non-placeholder UUID"
            )
