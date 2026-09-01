# Implementation checklist

Use this while wiring BlazeDB into your app. Do one phase at a time. Check items off as you go. Stuck? Open <doc:QuickReference> first.

## Phase 0: Package and open

- [ ] Add BlazeDB package (local path or GitHub)
- [ ] Depend on the **BlazeDB** product
- [ ] Create `SeekerDatabase` (or similar) with `BlazeDBClient.open(named:password:)` **once** in `shared`
- [ ] Use `do` / `catch` in `shared` and `throws` on `init` (avoid `try!` in app code)
- [ ] Store password in Keychain (not hardcoded in source)
- [ ] Confirm the app launches without a database error

## Phase 1: One model, one list

- [ ] Define one ``BlazeStorable`` model (`UUID` id, `Codable` fields)
- [ ] Add `.blazeDBEnvironment(SeekerDatabase.shared.db)` on the root `WindowGroup`
- [ ] Add `@BlazeStorableQuery(kind: YourModel.self)` on a list screen
- [ ] Render `List(items) { ... }`
- [ ] If the list is empty, verify injection (see <doc:SwiftUIIntegration>)

## Phase 2: Writes and updates

- [ ] Read the `blazeDBClient` environment value in the screen that writes
- [ ] `guard let db else { return }` before writes
- [ ] Insert with `put(_:)`
- [ ] Update by mutating the model and `put` again (same `id`)
- [ ] Confirm the list refreshes without manual `@State` for the full array

## Phase 3: Detail screen

- [ ] `NavigationLink` to a detail view, or pass the row model
- [ ] Optional: re-fetch with `get(_:)` using `"namespace:\(id.uuidString)"`
- [ ] Add edit + save via `put`

See <doc:AppPatterns>.

## Phase 4: Filters and tabs (optional)

- [ ] Add a `status` (or similar) field on the model
- [ ] One tab or screen per filter with its own `@BlazeStorableQuery(where:equals:)`
- [ ] Or group in SwiftUI with `Dictionary(grouping:)` on one query

## Phase 5: Related data (optional)

- [ ] Child model with `parentId: UUID` (or `jobId`, etc.)
- [ ] Filtered `@BlazeStorableQuery` on the detail screen
- [ ] `put` child rows from the detail screen
- [ ] `delete(id:)` when removing rows (no automatic cascade)

See <doc:RelatedData>.

## Phase 6: Location (optional)

- [ ] Add `latitude` and `longitude` as `Double` on the model
- [ ] `try db.enableSpatialIndex()` after open
- [ ] Use `db.query().withinRadius` / `.near` (not `@BlazeStorableQuery`)
- [ ] For a small beta, filter client-side on a live query instead

See <doc:LocationQueries>.

## Phase 7: Polish

- [ ] Surface `$query.error` and `$query.isLoading` where it matters
- [ ] Previews: `@BlazeStorableQuery(db: previewDB, kind: ...)`
- [ ] Handle write errors (do not only use `try?` in production paths)
- [ ] One ``BlazeDBClient`` per database; do not open a new client per screen

## Quick reminders

| Task | API |
|------|-----|
| Open | `SeekerDatabase.shared` → ``BlazeDBClient/open(named:password:)`` |
| Inject | `.blazeDBEnvironment(SeekerDatabase.shared.db)` |
| Live list | ``BlazeStorableQuery`` |
| Write | the `blazeDBClient` environment value + `put` |
| Read one | `get("namespace:<uuid>")` |
| Delete | `delete(id:)` |
| Nearby | `query()` + `withinRadius` |

## When you feel overwhelmed

1. Read <doc:QuickReference> (one page)
2. Implement Phase 0 through Phase 2 only
3. Ship that
4. Add Phase 4+ when the UI needs them

You do not need every article on day one.
