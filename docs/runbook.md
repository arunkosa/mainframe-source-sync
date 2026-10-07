# Runbook

## Purpose

This runbook explains how to set up, run, validate, and troubleshoot `mainframe-source-sync` in a z/OS USS environment. It is the operational companion to [docs/architecture.md](architecture.md) and the repository overview in [README.md](../README.md).

## Scope

This project copies exported mainframe source into a Git repository through a shell sync script, with optional JCL and `BPXBATCH` wrappers for batch execution. The runbook covers:

- runtime configuration and directory layout
- target repository bootstrap for an empty repo
- sample JCL and `BPXBATCH` execution flow
- logs, return codes, and troubleshooting
- operational checks and test commands

## Dependencies

The core sync flow depends on the following components being available and correctly configured:

- Bash in USS
- Git at the path defined by `GIT_BIN`
- SSH at the path defined by `SSH_BIN`
- a writable target Git repository clone
- a source export directory populated by your upstream process
- an external runtime configuration file if you do not want to rely on the tracked template

If you choose the sample batch adapter, you also need:

- JCL and PROC members under `jcl/`
- `BPXBATCH`
- any site-specific scheduler or downstream job steps you keep in the sample JCL

## Suggested directory layout

The runtime and working directories are intentionally separated. One practical layout is:

- `/u/<user>/projects/mainframe-source-sync` as the runtime and configuration area
- `/u/<user>/git_repos/open-source/mainframe-source-sync` as the checked-out framework repository
- `/u/<user>/git_repos/target/source-mirror` as the target Git working tree that receives synchronized source

Within the runtime area, the important files and folders are:

- `config/app_config.txt` for the sample JCL and `BPXBATCH` adapter
- `config/sync.env` as the active runtime config for the sync script
- `logs/` for per-run log files written by the sync script

## Configuration model

The job uses two layers of configuration:

1. `config/app_config.txt` is the adapter entry-point config. The sample PROC passes it to `BPXBATCH` as `STDENV`, which makes `PROJECT_WORKSPACE`, `PROJECT_NAME`, and `PROJECT_CONFIG` available before Bash starts.
2. The sync script reads the actual runtime settings from `sync.env`. That file defines the source path, target path, Git remote and branch, Git and SSH binary paths, author identity, retry behavior, and log settings.

The runtime config resolution order is:

1. an explicit `-c /path/to/sync.env` argument
2. `PROJECT_CONFIG` from `config/app_config.txt`
3. `config/sync.env.template` as a local fallback

Do not treat `config/sync.env.template` as a production runtime file. It is a reference copy.

### Key runtime variables

- `PROJECT_WORKSPACE` points at the parent directory of this repository checkout.
- `PROJECT_NAME` is the repository folder name inside `PROJECT_WORKSPACE`.
- `PROJECT_CONFIG` points at the external runtime `sync.env`.
- `SOURCE_BASE_DIR` is the upstream export root.
- `TARGET_BASE_DIR` is the target Git working tree.
- `GIT_BIN` is the full path to Git.
- `SSH_BIN` is the full path to SSH.
- `GIT_REMOTE` is usually `origin`.
- `GIT_BRANCH` is usually `main`.
- `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` define the commit identity used in the target repo.
- `LOG_DIR` is the directory for timestamped run logs.

## Initial setup

### 1. Prepare the framework repository

Clone this project into a stable USS-accessible location:

```bash
cd /u/<user>/git_repos/open-source
git clone <your-fork-or-origin-url> mainframe-source-sync
cd mainframe-source-sync
```

Confirm that the checkout contains the expected layout before you proceed:

- `bin/`
- `config/`
- `docs/`
- `jcl/`
- `lib/`
- `tests/`

### 2. Prepare the target repository

If the target repository is empty, initialize it before the first sync so the remote branch exists.

Copy the bootstrap metadata into the empty repo first:

```bash
cd /u/<user>/git_repos/target
git clone <target-repo-url> source-mirror
cd source-mirror
cp /u/<user>/git_repos/open-source/mainframe-source-sync/config/target_repo_bootstrap/.gitattributes .
cp /u/<user>/git_repos/open-source/mainframe-source-sync/config/target_repo_bootstrap/.gitignore .
git add .gitattributes .gitignore
git commit -m "Bootstrap repository metadata"
git push -u origin main
```

### 3. Create the external runtime config

Copy the tracked template into the runtime area and rename it to `sync.env`:

```bash
mkdir -p /u/<user>/projects/mainframe-source-sync/config
cp /u/<user>/git_repos/open-source/mainframe-source-sync/config/sync.env.template \
   /u/<user>/projects/mainframe-source-sync/config/sync.env
```

Set the environment-specific values in that file. At minimum, verify:

- `SOURCE_BASE_DIR`
- `TARGET_BASE_DIR`
- `GIT_BIN`
- `SSH_BIN`
- `GIT_REMOTE`
- `GIT_BRANCH`
- `GIT_AUTHOR_NAME`
- `GIT_AUTHOR_EMAIL`
- `GIT_PUSH_RETRY_COUNT`
- `GIT_PUSH_RETRY_DELAY_SECONDS`
- `LOG_DIR`

### 4. Point the adapter runtime at the config

If you use the sample JCL and `BPXBATCH` adapter, update `config/app_config.txt` so `PROJECT_WORKSPACE`, `PROJECT_NAME`, and `PROJECT_CONFIG` match your environment.

### 5. Verify filesystem access

Before running the job, confirm that the batch or interactive user can access:

- the runtime/configuration directory
- the framework repository checkout
- the target repository checkout
- the export source directory
- the Git and SSH binaries configured in `sync.env`

## Running the sync

### Manual execution

For local testing or interactive troubleshooting, run from the repository root:

```bash
cd /u/<user>/git_repos/open-source/mainframe-source-sync
bash bin/sync_mainframe_source.sh
```

Use `-c` only when you want to override the runtime config for a specific test.

Common options:

```bash
bash bin/sync_mainframe_source.sh -n
bash bin/sync_mainframe_source.sh -c /u/<user>/projects/mainframe-source-sync/config/sync.env
bash bin/sync_mainframe_source.sh -c /u/<user>/projects/mainframe-source-sync/config/sync.env -l /path/to/libraries.conf
```

### Batch execution with the sample adapter

The included sample path is:

`Scheduler -> JCL Job (SYNCGIT) -> PROC (SYNCGIT.prc) -> BPXBATCH -> bin/sync_mainframe_source.sh`

The JCL files under `jcl/` are examples. Replace scheduler details, job cards, and downstream hooks with values that match your environment.

## What the sync does

The sync script performs the following actions in order:

1. sources `config/app_config.txt` to resolve `PROJECT_WORKSPACE`, `PROJECT_NAME`, and `PROJECT_CONFIG`
2. loads the runtime `sync.env`
3. validates the configured Git and SSH binary paths
4. initializes logging in `LOG_DIR`
5. verifies that `SOURCE_BASE_DIR` and `TARGET_BASE_DIR` exist
6. validates that `TARGET_BASE_DIR` is a Git repository
7. sets or preserves the local Git identity in the target repo
8. fast-forwards the target repo from `GIT_REMOTE/GIT_BRANCH`
9. ensures `.gitattributes` and `.gitignore` are present in the target repo
10. loads `config/libraries.conf`
11. copies each listed export directory from source to target
12. checks whether changes or unpushed commits exist
13. commits and pushes when needed, or exits with RC `4` when nothing changed

## Return codes

| RC | Meaning | Operator action |
|---|---|---|
| 0 | Changes were committed and pushed successfully | No action required |
| 4 | No changes were detected, so commit/push was skipped | No action required |
| 8 | Configuration error | Check config files, executable paths, and filesystem layout |
| 12 | Processing error | Check export directories and copy failures |
| 16 | Git error | Check Git, SSH, remote access, and branch state |
| 20 | Unexpected fatal error | Review the logs and adapter output |

## Logs and output

Each run writes a timestamped log file under `LOG_DIR`, for example:

```text
/u/<user>/projects/mainframe-source-sync/logs/sync_mainframe_to_github_<timestamp>.log
```

If you use the sample JCL wrapper, the job also writes to `SYSPRINT`, `STDOUT`, and `STDERR`.

The log captures:

- configuration resolution
- source and target directory validation
- library copy results
- Git identity and branch checks
- commit and push activity
- retry attempts and push failures
- dry-run behavior

## Operational checks

Use these checks before and after a production run:

- verify `config/app_config.txt` points to the correct external `sync.env` if you use the sample adapter
- verify `sync.env` contains valid executable paths for Git and SSH
- verify the target repo has `.gitattributes` and `.gitignore` before the first run
- verify `SOURCE_BASE_DIR` contains the exported libraries you expect
- verify `TARGET_BASE_DIR` is a valid Git checkout
- verify the log directory exists and is writable
- verify the runtime user can authenticate to the Git remote

## Library maintenance

To add or remove libraries from the sync job:

1. edit `config/libraries.conf`
2. add one export directory name per line
3. use `#` for comments
4. rerun the job or script after the file is updated

## Validation and tests

Run the shell tests from the repository root:

```bash
bash tests/test_git_ops.sh
bash tests/test_logging.sh
bash tests/test_file_ops.sh
```

## Troubleshooting

### Configuration problems

Symptoms:

- the job stops before the copy phase
- the script exits with RC `8`
- the log says the config file, source directory, or target directory cannot be found

Check:

- `config/app_config.txt`
- `sync.env`
- `SOURCE_BASE_DIR`
- `TARGET_BASE_DIR`
- `GIT_BIN`
- `SSH_BIN`

### Empty target repository

Symptoms:

- Git operations fail early
- the job cannot fast-forward or push

Check:

- the target repo has an initial commit
- the configured branch exists on the remote
- bootstrap files were copied before the first sync
- `TARGET_BASE_DIR` does not have the expected bootstrap metadata

Check that `.gitattributes` and `.gitignore` were copied from `config/target_repo_bootstrap/` into the target repo before the first sync.

### Git push failures

Symptoms:

- the job reaches the push step and fails with RC 16
- the log shows remote access or authentication errors
- the push retry loop is used repeatedly

Check:

- SSH key access for the job user
- the configured SSH binary path
- remote connectivity to GitHub
- branch state and upstream tracking
- any merge conflicts or non-fast-forward conditions

### Copy failures

Symptoms:

- the job exits with RC 12
- one or more libraries fail to copy
- the log shows missing source files or permissions issues

Check:

- the library is listed in `config/libraries.conf`
- the source export exists under `SOURCE_BASE_DIR`
- the source path is readable by the job user
- the target path is writable by the job user

### Log review

If a job fails and the cause is not obvious, review the latest timestamped file under `LOG_DIR` and the JCL output from `STDOUT` / `STDERR`.

## Maintenance Notes

- Keep `config/sync.env.template` as the tracked reference copy.
- Keep the active `sync.env` outside the repository.
- Keep the target repo bootstrap files available under `config/target_repo_bootstrap/` for empty-repo initialization.
- Update [docs/architecture.md](architecture.md) when pipeline or configuration behavior changes.
- Update this runbook whenever setup or operational steps change.

## See Also

- [README.md](../README.md)
- [docs/architecture.md](architecture.md)
