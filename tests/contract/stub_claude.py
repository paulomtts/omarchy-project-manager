"""A stub `claude` for the contract tests: writes each agent phase's result from the brief alone.

Test infrastructure, standard library only, run as a script under a `#!<python>` line. The
brief path is the value after `-p` (`Read <path> and follow the instructions in it exactly.`);
the phase is the brief's `# phase: <name>` header, the result path the line after `write your
result as valid JSON to exactly this path:` in `## Result contract`, the JSON Schema that
section's ```json fence, and the phase inputs its `## <name>` sections. The result is every
schema property at its type's zero value, then the fields the phase's gates need. A field the
schema lacks, or a phase with no behaviour here, exits 1 naming it on stderr. On success it
prints exactly `stub claude ok phase=<phase>` and exits 0.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

PROMPT_SENTENCE = re.compile(r"^Read (?P<path>.+?) and follow the instructions in it exactly\.")
PHASE_HEADER = re.compile(r"^# phase: (?P<phase>\S+)$", re.M)
RESULT_HEADING = "## Result contract"
RESULT_PATH_LEAD = "write your result as valid JSON to exactly this path:"
SCHEMA_FENCE = re.compile(r"```json\n(?P<schema>.*?)\n```", re.S)
SECTION = re.compile(r"^## (?P<name>.+)$", re.M)
# Longer than am's minimum summary length (60).
SUMMARY = ("the stub claude wrote this result from the brief on disk alone: the schema's zero "
           "values plus the fields this phase's gates read")
# The scratch HOME has no git identity.
GIT_IDENTITY = ("-c", "user.name=stub", "-c", "user.email=stub@example.com")


class StubError(Exception):
    pass


def brief_path(argv):
    if "-p" not in argv or argv.index("-p") + 1 >= len(argv):
        raise StubError(f"no -p argument in argv: {argv!r}")
    sentence = argv[argv.index("-p") + 1]
    found = PROMPT_SENTENCE.match(sentence)
    if found is None:
        raise StubError(f"the -p text is not the brief sentence: {sentence!r}")
    return Path(found.group("path"))


def phase_of(text):
    found = PHASE_HEADER.search(text)
    if found is None:
        raise StubError("the brief carries no `# phase:` header")
    return found.group("phase")


def contract_of(text):
    start = text.find(RESULT_HEADING)
    if start < 0:
        raise StubError(f"the brief has no {RESULT_HEADING!r} section")
    return text[start:]


def result_path_of(text):
    contract = contract_of(text)
    lead = contract.find(RESULT_PATH_LEAD)
    if lead < 0:
        raise StubError(f"the result contract does not say {RESULT_PATH_LEAD!r}")
    for line in contract[lead + len(RESULT_PATH_LEAD):].splitlines():
        if line.strip():
            return Path(line.strip())
    raise StubError("the result contract names no path")


def schema_of(text):
    found = SCHEMA_FENCE.search(contract_of(text))
    if found is None:
        raise StubError("the result contract embeds no ```json schema fence")
    return json.loads(found.group("schema"))


def sections(text):
    """Every `## <name>` section after the `# phase:` header; the first of a name wins."""
    head = PHASE_HEADER.search(text)
    body = text[head.end():] if head is not None else text
    marks = list(SECTION.finditer(body))
    found = {}
    for index, mark in enumerate(marks):
        end = marks[index + 1].start() if index + 1 < len(marks) else len(body)
        found.setdefault(mark.group("name"), body[mark.end():end].strip("\n"))
    return found


def section(found, name, phase):
    if name not in found:
        raise StubError(f"the {phase!r} brief has no `## {name}` section")
    return found[name].strip()


def zero_payload(schema, defs=None):
    """Every property of `schema` at its type's zero value; `$ref` resolves through `$defs`."""
    table = schema.get("$defs", {}) if defs is None else defs
    return {name: zero_value(node, table) for name, node in schema.get("properties", {}).items()}


def zero_value(node, defs):
    if "$ref" in node:
        name = node["$ref"].rsplit("/", 1)[-1]
        if name not in defs:
            raise StubError(f"the schema references unknown $def {name!r}")
        return zero_payload(defs[name], defs)
    if "anyOf" in node:
        if any(option.get("type") == "null" for option in node["anyOf"]):
            return None
        return zero_value(node["anyOf"][0], defs)
    kind = node.get("type")
    if kind == "object":
        return zero_payload(node, defs)
    if kind == "array":
        return []
    if kind == "string":
        return ""
    if kind in ("integer", "number"):
        return 0
    if kind == "boolean":
        return False
    raise StubError(f"no zero value for schema node {node!r}")


def override(payload, **fields):
    """Set each field, refusing a name the schema did not produce."""
    for name, value in fields.items():
        if name not in payload:
            raise StubError(f"the schema has no field {name!r} (it has: {sorted(payload)})")
        payload[name] = value
    return payload


def git(*args):
    proc = subprocess.run(["git", *GIT_IDENTITY, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise StubError(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout


def write_document(relative, kind):
    path = Path(relative)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# {kind} for this card\n", encoding="utf-8")


def build_result(phase, payload, found):
    if phase == "explore":
        suite = json.loads(section(found, "verification", phase))
        override(payload["verification"], full_suite=suite, typecheck="", lint=[])
        return override(payload, refused=False, reason=None, summary=SUMMARY,
                        verification=payload["verification"])
    if phase in ("validate_spec", "validate_plan"):
        return override(payload, blockers=False, reason=None, summary=SUMMARY)
    if phase == "spec":
        relative = section(found, "spec_path", phase)
        write_document(relative, "spec")
        return override(payload, path=relative, note=None)
    if phase == "plan":
        relative = section(found, "plan_path", phase)
        write_document(relative, "plan")
        return override(payload, path=relative, self_reviewed=True, note=None)
    if phase == "implement":
        digest = section(found, "plan_hash", phase)
        relative = section(found, "plan_path", phase)
        Path("IMPLEMENTATION.md").write_text(f"# implementation of {relative}\n", encoding="utf-8")
        git("add", "-A")
        resumed = git("status", "--porcelain").strip() == ""
        if not resumed:
            git("commit", "-m", f"feat: implement this card\n\nPlan-Hash: {digest}")
        return override(payload, blocked=False, blocked_reason=None, resumed=resumed,
                        plan_hash=digest, report=SUMMARY)
    if phase == "review":
        base = section(found, "base_branch", phase)
        digest = section(found, "plan_hash", phase)
        revisions = git("rev-list", f"{base}..HEAD").split()
        tagged = [revision for revision in revisions
                  if f"Plan-Hash: {digest}" in git("show", "-s", "--format=%B", revision)]
        return override(payload, findings=[], unresolved_blockers=[], fix_summary=SUMMARY,
                        porcelain=git("status", "--porcelain").strip(),
                        commit_count=len(revisions), tagged_count=len(tagged), plan_hash=digest)
    raise StubError(f"no behaviour for phase {phase!r}")


def main(argv):
    text = brief_path(argv).read_text(encoding="utf-8")
    phase = phase_of(text)
    result_path = result_path_of(text)
    payload = build_result(phase, zero_payload(schema_of(text)), sections(text))
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"stub claude ok phase={phase}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except StubError as error:
        print(f"stub claude: {error}", file=sys.stderr)
        sys.exit(1)
