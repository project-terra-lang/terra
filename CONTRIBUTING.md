# Contributing

This repository is archived and is not seeking upstream contributions.

You are welcome to fork the project and continue it independently. The license
allows any use, including commercial use, redistribution, relicensing in your
own derived work, and publishing modified versions without attribution.

## Suggested Direction For Forks

Terra was intentionally kept small and incremental. If you continue it, the most
natural path is to keep changes focused:

- Preserve Erlang/BEAM compatibility unless your fork has a different runtime
  goal.
- Add syntax only when it gives a clear static guarantee.
- Keep examples and tests close to each language feature.
- Update `README.md`, `TODO.md`, `Progress.md`, and
  `docs/language-reference-v0.md` when behavior changes.
- Run `./build.sh --test` before publishing changes.

Forks do not need to follow this guidance. It is only here to help future
maintainers understand the original project style.
