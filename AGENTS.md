# Codex Agent Instructions

Always read `README.md` before making changes, answering project-specific questions, or deciding how this codebase should evolve.

Treat `README.md` as the source of truth for the Terra language design, project goals, and implementation direction. If code and README guidance disagree, pause and reconcile the mismatch before changing behavior.

This repository is a small Erlang/escript research project for a simple Terra language transpiler. Keep work aligned with the README's current direction:

- Keep the language simple and incremental.
- Favor Erlang ecosystem compatibility.
- Preserve the research-project style and avoid adding complete production-grade systems unless the README calls for them.
- Add features over time in small, understandable steps.
- Keep the codebase structure close to the way it was originally made, improving that structure gradually instead of replacing it all at once.
- When adding or extending a feature, preserve the existing feature structure and build on it.
- If an existing feature has issues, fix those issues as part of the improvement while keeping the feature's intended shape.

Before editing code, check the relevant README section again and make sure the change supports that documented intent.
