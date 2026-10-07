# Adapters

## Purpose

This project separates reusable sync behavior from environment-specific integration points.

The shell libraries and the main entrypoint form the core sync engine. Scheduler setup, JCL wrappers, USS launch mechanics, export conventions, and post-sync processing are adapters.

## Core components

The core of the project is made up of:

- `bin/sync_mainframe_source.sh`
- `lib/file_ops.sh`
- `lib/git_ops.sh`
- `lib/logging.sh`
- `lib/error_handling.sh`
- `config/sync.env.template`
- `config/libraries.conf`

These files should stay as neutral as possible and avoid assumptions about one company, one scheduler, or one source-management product.

## Current adapters

The repository currently includes these sample adapters:

- `config/app_config.txt` as a sample `STDENV`-style entrypoint config
- `jcl/jobs/SYNCGIT.jcl` as a sample batch job wrapper
- `jcl/procs/SYNCGIT.prc` as a sample `BPXBATCH` launch PROC

These files are examples, not required framework internals.

The current z/OS adapter boundary is summarized in [../adapters/zos/README.md](../adapters/zos/README.md).

## Adapter boundaries

Keep these concerns outside the core engine whenever possible:

- scheduler-specific behavior
- job card values and routing
- site-specific downstream hooks
- source-export naming conventions that are unique to one environment
- repository hosting assumptions beyond standard Git operations

## Future direction

Good next adapter extractions would be:

- optional scheduler examples for cron, Control-M, or CI
- optional downstream hook examples that run after a successful sync
- optional source adapters for different export producers
- a deeper separation between reusable config contracts and adapter-owned launch configuration