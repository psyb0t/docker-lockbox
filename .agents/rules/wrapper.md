# Wrapper

Applies to `lockbox-wrapper`.

- Standard library only. The image installs `python3` and nothing from pip, so a third-party import breaks every connection.
- Never run a shell. Parse with `shlex.split()` and start external commands with `os.execv()`. No `subprocess` with `shell=True`, no `os.system`.
- Every user-supplied path goes through `safe_path()` before any filesystem call, and a `None` result ends in `die("path outside /work")` (or the source/destination variant). Commands that must not touch `/work` itself check `target == WORK_DIR`, as the remove commands do.
- Report errors with `die(msg)`: `Error: <msg>` on stderr, exit 1. Keep existing messages word for word, because `test.sh` greps for them and downstream users script against them.
- A new built-in is a `cmd_<name>(args)` function, a name in `BUILTINS`, an entry in the `builtins` dict in `main()`, tests in `test.sh`, and a row in `docs/file-operations.md`.
- Stream file data in 64 KiB chunks through `sys.stdin.buffer` and `sys.stdout.buffer`, as `get`, `put` and `append-file` do. Do not read whole files into memory.
- Early returns, no `else` after a branch that returns or dies.
- `make lint-python` runs flake8 at line length 88 (black's default) and must stay clean.
