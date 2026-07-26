# blazerepl Homebrew Tap

Install the BlazeDB CLI with Homebrew using the `blazerepl` formula.

This tap installs:

- `blazedb` (canonical command)
- `blazerepl` (alias to `blazedb`)

Both commands run the same binary.

## Install

```bash
brew update
brew tap Mikedan37/blazedb
brew install blazerepl
```

## Verify

```bash
which blazedb
which blazerepl
blazedb --help
```

The help output should include `blazedb start`.

## Basic Usage

Start the interactive database picker + REPL:

```bash
blazedb start
```

or:

```bash
blazerepl start
```

Open a specific database file directly:

```bash
blazedb "/absolute/path/to/database.blazedb"
```

## Common REPL Commands

```text
fetchAll
fetch <row-index>
fetch <uuid>
query <field> <op> <value>
help
exit
```

Examples:

```bash
query role = assistant and project = Default sort createdAt desc limit 20
fetch 1
fetch 1 --json
```

## Upgrade

```bash
brew update
brew upgrade blazerepl
```

## Uninstall

```bash
brew uninstall blazerepl
brew untap Mikedan37/blazedb
```

## Troubleshooting

### `blazedb` not found after install

Check your PATH and Homebrew prefix:

```bash
brew --prefix
which -a blazedb
```

### Install fails while building Swift package

Install/update Xcode Command Line Tools:

```bash
xcode-select --install
```

Then retry:

```bash
brew install blazerepl
```

### Command points to an old binary

If you have multiple copies installed:

```bash
which -a blazedb
```

Ensure the Homebrew path is first, or remove stale copies.

