# z/OS Adapter

## Purpose

This directory documents the z/OS-specific adapter layer for `mainframe-source-sync`.

The core engine remains shell-based and repository-hosting agnostic. The z/OS adapter covers how that core engine is launched in USS and batch-oriented environments.

## Current state

The repository currently keeps the sample z/OS assets in their original top-level locations:

- `config/app_config.txt`
- `jcl/jobs/SYNCGIT.jcl`
- `jcl/procs/SYNCGIT.prc`

Those files together form the current z/OS adapter example.

## Adapter responsibilities

The z/OS adapter is responsible for:

- providing `STDENV` values before the shell starts
- launching the sync script through `BPXBATCH`
- setting site-specific job-card and routing values
- deciding whether any downstream site-specific steps run after a successful sync

## What should stay out of the core engine

These concerns belong in the adapter, not in the core shell libraries:

- JCL job cards and output classes
- scheduler-specific conventions
- downstream utilities unique to one installation
- site-specific repo paths and export path conventions

## Planned direction

Over time, the sample z/OS files can be moved under a more explicit adapter layout. Until then, use this document as the boundary reference when deciding where changes belong.