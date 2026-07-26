# BlazeDB Experiments

Experiments are repository-local developer workflows discovered by:

```bash
blazedb dev experiments
```

Each experiment lives in its own directory:

```text
Experiments/<name>/
  experiment.json
  run.sh
```

Example manifest:

```json
{
  "name": "btree-search",
  "summary": "Run experimental B+ tree search checks",
  "command": "./Experiments/btree-search/run.sh"
}
```

Run it with:

```bash
blazedb dev experiment btree-search
```

Forward arguments with:

```bash
blazedb dev experiment btree-search -- --records 10000
```

## Rules

* Directory name must match the manifest `name`
* `name` must match `[a-z0-9][a-z0-9-]*`
* Commands must be relative to the repository root
* After resolving symlinks, the executable must stay inside the repository
* The declared executable must exist, be a regular file, and be executable
* Duplicate names are rejected
* Experiments are not tests; use `blazedb dev test` for tests
