# Scatterbrain agent rules

## Read first
Before making any code change, always read:
1. `AGENTS.md`
2. `docs/ENGINEERING_RULES.md`

## Required validation
After any code change, always run these commands in order:

1. `godot --version`
2. `godot --headless --import --path .`
3. `godot --headless --path . --quit`
4. `godot --headless --path . --script scripts/tests/headless_logic_harness.gd`

Rules:
- If step 2 fails, do not run step 3.
- If any step fails, include the exact command and full error output.
- Do not claim runtime validation passed unless all required steps succeed.

## Project rules
- `LevelRoot` is the single source of truth for levels.
- Do not add compatibility layers, fallback paths, or dual data sources unless explicitly requested.
- Any editor-visible gameplay element must have matching runtime semantics.
- Update `docs/ENGINEERING_RULES.md` whenever architecture, workflow, level-loading rules, or engineering boundaries change.

## Change discipline
- Prefer minimal, targeted changes.
- Do not introduce temporary compatibility code.
- When fixing gameplay logic, prioritize runtime truth over editor-only presentation.
- If a task changes architecture or data flow, update documentation in the same change.
