//
//  CLIHelp.swift
//  BlazeCLICore
//

import Foundation

public enum CLIHelp {
  public static func printGlobal() {
    print(CLIBranding.heroLines().joined(separator: "\n"))
    print(
      """
      \(CLIColors.bold("Getting started"))
        \(CLIColors.ice("blazedb start"))          Scan Mac → pick database → REPL
        \(CLIColors.ice("blazedb"))                 Same as start
        \(CLIColors.ice("blazedb <file> [pass]"))   Open one database directly

      \(CLIColors.bold("More"))
        blazedb --create-test          Sample database for Visualizer
        blazedb --manager              Multi-database manager
        blazedb --master               Launch in master mode (vault flow)
        blazedb master <command>       Master keyring operations
        blazedb bookmark add <path>    Pin a path in the picker
        blazedb restore-backup <dest>  Restore ./lastKnownGood.blazedb

      \(CLIColors.muted("Tip: export BLAZEDB_PASSWORD=… to skip the unlock prompt."))
      \(CLIColors.muted("Master tip: BLAZEDB_MASTER_PASSWORD is for automation only; avoid in shell history."))
      """
    )
  }

  public static func printPicker() {
    print(
      """
      \(CLIColors.bold("blazedb picker")) — shortcuts

        \(CLIColors.ice("↑ / ↓"))     Move selection (wraps across pages)
        \(CLIColors.ice("[  /  ]"))   Previous / next page (10 per page)
        \(CLIColors.ice("n / p"))      Next / previous page
        \(CLIColors.ice("Enter"))    Open database
        \(CLIColors.ice("/"))         Filter by name (type, Enter to apply)
        \(CLIColors.ice("b"))         Toggle bookmarked-only filter
        \(CLIColors.ice("s"))         Rescan home directory
        \(CLIColors.ice("? / h"))     This help
        \(CLIColors.ice("q"))         Quit

      \(CLIColors.muted("Sorted newest created first. Press any key to return…"))
      """
    )
  }

  public static func printRepl(databaseName: String, databasePath: String) {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var displayPath = databasePath
    if displayPath.hasPrefix(home) {
      displayPath = "~" + displayPath.dropFirst(home.count)
    }
    print(
      """
      \(CLIColors.bold("BlazeDB shell")) — \(CLIColors.ice(databaseName))
      \(CLIColors.muted(displayPath))

      \(CLIColors.bold("Shortcuts"))
        \(CLIColors.ice("help"))  \(CLIColors.ice("?"))  \(CLIColors.ice("shortcuts"))   Show this screen
        \(CLIColors.ice("exit"))                              Leave the shell

      \(CLIColors.bold("Commands"))
        fetchAll                         List all records
        insert <json>                    Insert a document
        fetch <uuid>                     Fetch one record
        update <uuid> <json>             Replace a record
        softDelete <uuid>                Soft-delete
        delete <uuid>                    Hard-delete

      \(CLIColors.bold("Examples"))
        insert {"name": "Ada", "score": 99}
        fetch 550e8400-e29b-41d4-a716-446655440000

      \(CLIColors.muted("Outside the shell: blazedb start · blazedb --help"))
      """
    )
  }

  public static func printManager() {
    print(
      """
      \(CLIColors.bold("BlazeDB manager")) — shortcuts

        \(CLIColors.ice("help"))  \(CLIColors.ice("?"))     This screen
        \(CLIColors.ice("list"))                 Mounted databases
        \(CLIColors.ice("mount")) <name> <path> <password>
        \(CLIColors.ice("use")) <name>           Switch active DB
        \(CLIColors.ice("current"))              Show active DB
        \(CLIColors.ice("exit"))                 Quit
      """
    )
  }

  public static func printMaster() {
    print(
      """
      \(CLIColors.bold("BlazeDB master mode")) — keyring commands

        \(CLIColors.ice("blazedb master init"))           Initialize encrypted keyring (~/.blazedb/keyring.json.enc)
        \(CLIColors.ice("blazedb master add <db>"))       Add DB secret to master vault
        \(CLIColors.ice("blazedb master remove <db|id>")) Remove DB secret from master vault
        \(CLIColors.ice("blazedb master list"))           List keyring entries
        \(CLIColors.ice("blazedb master status"))         Show keyring status and security metadata
        \(CLIColors.ice("blazedb --master"))              Start picker/REPL in master-aware mode

      \(CLIColors.bold("Scopes"))
        \(CLIColors.ice("--scope persistent"))            Encrypted in keyring file (default)
        \(CLIColors.ice("--scope device"))                macOS Keychain backed
        \(CLIColors.ice("--scope session"))               In-memory for current process only

      \(CLIColors.bold("Security guardrails"))
        - No source code credential scanning
        - No password extraction from app files
        - No arbitrary filesystem secret discovery

      \(CLIColors.bold("Automation"))
        \(CLIColors.ice("BLAZEDB_MASTER_PASSWORD")) is supported for local automation/tests only.
        Treat shell history and CI logs as sensitive if you use it.
      """
    )
  }
}
