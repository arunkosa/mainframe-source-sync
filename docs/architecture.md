# Architecture

## Design goals

`mainframe-source-sync` is intended to be a reusable sync framework rather than a single-site automation drop. The design aims to keep the core sync logic independent from scheduler choice, JCL wrappers, source-management product, and downstream processing rules.

## Logical model

The repository currently has two layers:

1. Core sync layer: shell code that loads configuration, copies exported source into a Git working tree, detects changes, and pushes updates.
2. Adapter layer: site-facing wrappers and conventions such as JCL, `BPXBATCH`, scheduler integration, source-export layout, and optional downstream hooks.

See [docs/adapters.md](adapters.md) for the intended boundary between those layers.

## Reference pipeline

The included z/OS example uses this pipeline:

Scheduler -> JCL Job (`SYNCGIT`) -> PROC (`SYNCGIT.prc`) -> `BPXBATCH` -> `bin/sync_mainframe_source.sh`

That adapter is only one supported deployment model. Other adopters may run the same shell entry point from cron, another enterprise scheduler, CI, or an interactive USS session.

## Configuration model

The runtime configuration is intentionally split across two files with different responsibilities:

1. `config/app_config.txt` is the entry-point configuration used by the sample JCL and `BPXBATCH` adapter. It defines the project location and can point at an external runtime config file.
2. `sync.env` is the actual script runtime configuration consumed by `bin/sync_mainframe_source.sh`. It defines source and target paths, Git remote and branch, Git and SSH binary locations, author identity, retry behavior, and logging settings.

The tracked file in this repository is `config/sync.env.template`. Production-style runs are expected to use an external, untracked copy referenced by `PROJECT_CONFIG`, which prevents environment-specific paths from being overwritten by later pulls.

At runtime, the sync script resolves configuration in this order:

1. an explicit `-c /path/to/sync.env` argument
2. `PROJECT_CONFIG` from `config/app_config.txt`
3. `config/sync.env.template` as a fallback for local testing

## Suggested directory layout

One practical layout is to separate runtime state from the code checkout:

1. A runtime/configuration directory, for example `/u/<user>/projects/mainframe-source-sync`, containing:
	- `config/app_config.txt`
	- `config/sync.env`
	- `logs/`
2. A Git workspace area containing:
	- a checkout of this project
	- a separate checkout of the target repository that will receive synchronized source

This is a recommendation, not a hard requirement. The framework only requires readable source exports, a writable target Git working tree, and a valid runtime config.

## Sync flow

1. An upstream process exports source members into `SOURCE_BASE_DIR`.
2. `sync_mainframe_source.sh` copies each configured library from `SOURCE_BASE_DIR/<library>` into `TARGET_BASE_DIR/<library>`.
3. `git status --porcelain` is used to detect whether the copy introduced any changes.
4. If changes exist, the script stages, commits, and pushes them.
5. If no changes exist, commit and push are skipped and the script exits with RC `4`.
6. The script writes a timestamped log file under `LOG_DIR` and emits status messages to stdout/stderr.
7. If you use the sample JCL wrapper, the JCL decides whether to continue into any site-specific downstream steps.

## Components

| Component | Responsibility |
|---|---|
| `bin/sync_mainframe_source.sh` | Main orchestrator |
| `lib/logging.sh` | Timestamped, leveled logging to a per-run log file plus stdout/stderr |
| `lib/error_handling.sh` | Exit-code constants, `die()`, ERR/EXIT traps |
| `lib/file_ops.sh` | Library config parsing and file copy |
| `lib/git_ops.sh` | Git repo validation, change detection, add/commit/push with retry |
| `config/app_config.txt` | Sample adapter config for JCL and `BPXBATCH` launches |
| `config/libraries.conf` | List of export directories to synchronize |
| `config/sync.env.template` | Tracked reference template for paths, Git settings, retry values, and logging |
| `jcl/` | Sample z/OS JCL adapter |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success - changes committed and pushed |
| 4 | Success - no changes detected, commit/push skipped |
| 8 | Configuration error |
| 12 | Processing error |
| 16 | Git error |
| 20 | Unexpected or fatal error |
