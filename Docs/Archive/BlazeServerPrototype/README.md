# BlazeServer Prototype (Archived)

This directory contains the original `BlazeServer` prototype:

- **Purpose:** Minimal Linux bring-up process to prove BlazeDB persistence
  (start → write → persist → restart → read) using `BlazeDBClient`.
- **Status:** Internal prototype / spike, **not** part of the supported BlazeDB OSS surface.
- **Support:** Not wired into `Package.swift`, not guaranteed to build or be maintained.

For production usage, rely on:

- the core `BlazeDB` library and `BlazeDBClient` API, and
- the documented CLI tools (`BlazeShell`, `BlazeDoctor`, `BlazeDump`, `BlazeInfo`).

