# mainframe-source-sync

Framework and reference implementation for synchronizing exported mainframe source into a Git repository.

## Overview

`mainframe-source-sync` provides the shell logic needed to copy source exports from a mainframe-accessible location into a Git working tree, detect changes, and push updates to a remote branch. The repository also includes sample z/OS adapters for JCL and `BPXBATCH`-based execution.

The goal is portability. The core sync flow should be reusable across different source-management systems, scheduler setups, and site-specific downstream integrations.

## Current scope

Today, the repository includes:

- Bash orchestration for copy, change detection, commit, and push
- configuration templates for runtime and library selection
- sample JCL and `BPXBATCH` wrappers for z/OS USS execution
- target-repository bootstrap files for encoding and ignore rules
- smoke tests for file operations, logging, and Git helpers

## Repository layout

- `.github/` contains issue and pull request templates for contributors.
- `adapters/` documents environment-specific adapter boundaries.
- `bin/` contains the shell entry points.
- `config/` contains tracked templates and sample runtime pointers.
- `docs/` contains architecture and operations guidance.
- `jcl/` contains sample job and PROC members for z/OS adopters.
- `lib/` contains the shared shell helper functions.
- `tests/` contains smoke tests for the shell libraries.

## Quick start

1. Copy `config/sync.env.template` to an external, untracked `sync.env` file for your environment.
2. Update the copied `sync.env` with your source path, target repo path, Git binaries, and logging values.
3. Update `config/app_config.txt` if you plan to use the sample JCL and `BPXBATCH` adapter.
4. Review `config/libraries.conf` and replace the sample library names with your own export directories.
5. Run a dry run with `bash bin/sync_mainframe_source.sh -n` before enabling scheduled execution.

## Project status

This repository is being reshaped from a single-site automation package into a reusable open-source project. The current implementation is stable for the included z/OS shell flow, but some adapters are still reference examples rather than polished framework modules.

## Documentation

- [docs/architecture.md](docs/architecture.md) explains the core flow and adapter model.
- [docs/adapters.md](docs/adapters.md) explains what belongs in the core engine versus environment-specific wrappers.
- [adapters/zos/README.md](adapters/zos/README.md) describes the current z/OS adapter boundary.
- [docs/runbook.md](docs/runbook.md) covers setup, operation, validation, and troubleshooting.
- [CONTRIBUTING.md](CONTRIBUTING.md) explains how to propose changes.
- [SECURITY.md](SECURITY.md) explains how to report security issues.
