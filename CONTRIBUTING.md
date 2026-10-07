# Contributing

## Scope

This project accepts contributions that improve the reusable sync framework, the z/OS adapter examples, documentation, tests, and operational safety.

## Before you open a change

- open an issue for significant behavior changes or new adapters
- keep changes focused on one concern when possible
- avoid bundling unrelated cleanup with functional work

## Development expectations

- preserve portability across shell environments where practical
- keep site-specific assumptions out of the core sync logic
- prefer configuration and adapter hooks over hardcoded environment behavior
- update documentation when behavior or setup steps change
- add or update tests when you change shell helper behavior

## Validation

Run the smoke tests from the repository root before submitting changes:

```bash
bash tests/test_git_ops.sh
bash tests/test_logging.sh
bash tests/test_file_ops.sh
```

If you change JCL or adapter documentation, include a short explanation of how you validated the change.

## Pull requests

Each pull request should include:

- a concise description of the problem
- a concise description of the fix
- any compatibility or migration notes
- confirmation of the tests you ran