# Testing

- `make test` builds `psyb0t/lockbox:latest-test` and runs `test.sh`, which is what CI runs. It needs Docker, Bash, `ssh` and `ssh-keygen`, no credentials and no network beyond pulling the base image.
- `test.sh` counts passes and failures and exits 1 when any test fails.
- Add a check with `run_test <name> <ssh command> <grep pattern>` or `run_test_negative` for output that must not appear. Use `ssh_cmd_stdin` for commands that read stdin.
- Wrapper tests include the traversal case: `../../etc/...` must print `path outside /work`.
- Installer changes get a test that runs `create_installer.sh` on a config in `$TMPDIR` and greps the generated `install.sh`, as the environment, processing unit and `set_env` sections do.
- Containers started by a test use a `$$` suffix in their name and are removed in `cleanup` or right after the test.
