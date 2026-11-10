---
title: "File operations"
description: "Every lockbox built-in command: put, get, list-files, file-info, search-files and the rest, with arguments, output and errors."
nav_order: 3
---

# File operations

Every lockbox container has 15 built-in commands for moving files in and out of `/work` and managing them there. They are part of [`lockbox-wrapper`](https://github.com/psyb0t/docker-lockbox/blob/main/lockbox-wrapper) and work in every downstream image, whatever its [allowlist](configuration.md#allowed-commands) holds. A built-in always wins over an `allowed.json` entry with the same name.

## Paths

Every path is relative to `/work`:

- `notes.txt` and `/notes.txt` both mean `/work/notes.txt`. A leading `/` is stripped and the rest goes under `/work`, so `get /etc/passwd` looks for `/work/etc/passwd`.
- The wrapper resolves `..` and symlinks with `realpath` before it checks the result. Anything that lands outside `/work` fails with `Error: path outside /work` (or `source path outside /work` / `destination path outside /work` for two-path commands).
- An empty path means `/work` itself.

`search-files` is the exception: its pattern is not checked this way. See [search-files](#search-files).

Files and directories the wrapper creates get mode `664` and `775`, because it sets umask `002`.

## Errors and exit codes

A failed command prints `Error: <message>` on stderr and exits 1. Success exits 0. The messages are listed with each command below and in [Troubleshooting](troubleshooting.md).

## Command list

| Command | Arguments | What it does |
| --- | --- | --- |
| `put` | `<path>` | Write stdin to a file, replacing it if it exists |
| `get` | `<path>` | Write a file to stdout |
| `append-file` | `<path>` | Append stdin to an existing file |
| `list-files` | `[--json] [path]` | List `/work` or a subdirectory |
| `file-info` | `<path>` | JSON metadata for one file or directory |
| `file-exists` | `<path>` | Print `true` or `false` |
| `file-hash` | `<path>` | SHA-256 hex digest of a file |
| `disk-usage` | `[path]` | Total bytes of the files under a path |
| `search-files` | `<pattern>` | Recursive glob search |
| `create-dir` | `<path>` | Create a directory and any missing parents |
| `remove-file` | `<path>` | Delete a file |
| `remove-dir` | `<path>` | Delete an empty directory |
| `remove-dir-recursive` | `<path>` | Delete a directory and everything in it |
| `move-file` | `<src> <dst>` | Move or rename a file or directory |
| `copy-file` | `<src> <dst>` | Copy a file |

The examples use `lockbox@host`. Use your image's username and port.

### put

```bash
ssh lockbox@host "put input.txt" < input.txt
```

Reads stdin in 64 KiB chunks and writes it to the file. An existing file is replaced. The parent directory must exist: `put a/b/c.txt` with no `a/b` fails with `parent directory does not exist`. Run [`create-dir`](#create-dir) first.

### get

```bash
ssh lockbox@host "get output.txt" > output.txt
```

Streams the file to stdout unchanged, so binary files are safe. Fails with `no such file` if the path is missing or is a directory.

### append-file

```bash
echo "more data" | ssh lockbox@host "append-file output.txt"
```

Appends stdin to the end of the file. The file must already exist (`no such file` otherwise); use `put` to create it.

### list-files

```bash
ssh lockbox@host "list-files"
ssh lockbox@host "list-files subdir"
ssh lockbox@host "list-files --json"
```

Prints one entry per line, sorted by name, with a trailing `/` on directories. Hidden files are included. Pointing it at a file prints just that file's name. Fails with `no such file or directory` for a missing path.

`--json` can go before or after the path. It prints a JSON array with one object per entry, in the same format as [`file-info`](#file-info):

```json
[
  {
    "name": "a.txt",
    "size": 3,
    "modified": 1794295298,
    "isDir": false,
    "mode": "rw-rw-r--",
    "owner": "lockbox",
    "group": "lockbox",
    "links": 1
  }
]
```

### file-info

```bash
ssh lockbox@host "file-info output.txt"
```

Prints one JSON object on one line:

| Field | Meaning |
| --- | --- |
| `name` | Base name |
| `size` | Size in bytes |
| `modified` | Modification time, Unix seconds |
| `isDir` | `true` for a directory |
| `mode` | Permission bits as `rwxr-xr-x`, without the file type character |
| `owner`, `group` | Names, or the numeric ID when the container has no such user or group |
| `links` | Hard link count |

Symlinks are followed, so the fields describe the target. Fails with `no such file or directory`.

### file-exists

```bash
ssh lockbox@host "file-exists output.txt"
```

Prints `true` or `false` and exits 0 either way. A path outside `/work` prints `false` instead of an error.

### file-hash

```bash
ssh lockbox@host "file-hash output.txt"
```

Prints the SHA-256 digest as 64 lowercase hex characters. Fails with `no such file` for a missing path or a directory.

### disk-usage

```bash
ssh lockbox@host "disk-usage"
ssh lockbox@host "disk-usage subdir"
```

Prints a byte count. For a file, that is its size. For a directory, it is the sum of the sizes of every file under it, so it counts content, not disk blocks the way `du` does. Symlinked directories are not followed.

### search-files

```bash
ssh lockbox@host "search-files **/*.txt"
```

Runs a Python `glob` with `**` matching any number of directories, starting from `/work`. Prints matches relative to `/work`, sorted, with a trailing `/` on directories. Names starting with `.` are not matched. No match prints nothing and exits 0.

The pattern does not go through the `/work` check the other commands use. `search-files ../etc/*` and `search-files /etc/*` print file names outside `/work`. They cannot read the files, but they do reveal what exists in the container. See [Security](security.md#known-gaps).

### create-dir

```bash
ssh lockbox@host "create-dir project1/raw"
```

Creates the directory and any missing parents, like `mkdir -p`. An existing directory is not an error.

### remove-file

```bash
ssh lockbox@host "remove-file input.txt"
```

Deletes a file. Fails with `is a directory, not removing` on a directory and `no such file or directory` on a missing path. Because the path is resolved first, pointing it at a symlink deletes the file the symlink points to, as long as that file is inside `/work`.

### remove-dir

```bash
ssh lockbox@host "remove-dir project1"
```

Deletes an empty directory. Fails with `directory not empty`, `not a directory`, or `cannot remove /work`.

### remove-dir-recursive

```bash
ssh lockbox@host "remove-dir-recursive project1"
```

Deletes the directory and everything in it, with no confirmation. Refuses `/work` itself with `cannot remove /work`, and fails with `not a directory` on a file.

### move-file

```bash
ssh lockbox@host "move-file old.txt new.txt"
```

Renames a file or a directory. The source must exist and the destination's parent directory must exist (`destination parent directory does not exist`). An existing destination file is replaced.

### copy-file

```bash
ssh lockbox@host "copy-file original.txt backup.txt"
```

Copies a file, keeping its modification time and mode. Directories are not supported: the source must be a file (`no such file` otherwise). If the destination is an existing directory, the copy goes inside it under the same name.
