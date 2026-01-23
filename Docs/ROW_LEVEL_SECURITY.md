# Row-Level Security (RLS) for Graph Queries

BlazeDB provides optional Row-Level Security (RLS) integration for graph queries, allowing you to filter data based on user roles and permissions. This feature is **completely optional** and **non-breaking** - if you don't configure RLS, BlazeDB behaves exactly the same as before.

## Overview

RLS for graph queries allows you to:
- Filter graph data based on user roles (admin/engineer/viewer)
- Restrict access to records based on team membership
- Combine RLS filters with user-defined filters
- Bypass RLS for admin users

All RLS filtering is **additive** and **non-invasive** - it wraps the existing query system without modifying core engine behavior.

## Quick Start

### 1. Enable RLS

```swift
let db = try BlazeDBClient(name: "myapp", fileURL: url, password: "secret")
db.rls.enable()
```

### 2. Define Security Policies

```swift
// Policy: Users can only see records from their team
db.rls.addPolicy(SecurityPolicy(
 name: "team_access",
 operation:.select,
 type:.restrictive
) { record, context in
 guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
 return context.teamIDs.contains(teamID)
})
```

### 3. Use Graph Queries with User Context

```swift
let userContext = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])
let points = try db.graph(for: userContext) {
 $0.x("createdAt",.day)
.y(.count)
}.toPoints()
```

## User Roles

BlazeDB provides three built-in roles:

### Admin
- **Bypasses all RLS policies**
- Sees all records regardless of policies
- Use `BlazeUserContext.admin()` to create

### Engineer
- Subject to RLS policies
- Typically sees team-based records
- Use `BlazeUserContext.engineer(userID:teamIDs:)` to create

### Viewer
- Subject to RLS policies
- Typically sees only assigned records
- Use `BlazeUserContext.viewer(userID:teamIDs:)` to create

## Creating User Context

```swift
// Admin (bypasses RLS)
let admin = BlazeUserContext.admin()

// Engineer on specific teams
let engineer = BlazeUserContext.engineer(
 userID: userID,
 teamIDs: [team1ID, team2ID]
)

// Viewer
let viewer = BlazeUserContext.viewer(
 userID: userID,
 teamIDs: []
)
```

## Graph Query Integration

### Basic Usage

```swift
let userContext = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])

// Graph query with RLS
let points = try db.graph(for: userContext) {
 $0.x("category")
.y(.count)
}.toPoints()
```

### With Additional Filters

RLS filters are applied **before** user-defined filters:

```swift
let points = try db.graph(for: userContext) {
 $0.x("status")
.y(.count)
.filter { $0.storage["priority"]?.intValue?? 0 > 5 } // User filter
}.toPoints()

// Effective filter: RLSFilter && UserFilter
```

### Date Binning with RLS

```swift
let points = try db.graph(for: userContext) {
 $0.x("createdAt",.day)
.y(.sum("amount"))
}.toPoints()
```

### Moving Windows with RLS

```swift
let points = try db.graph(for: userContext) {
 $0.x("createdAt",.day)
.y(.sum("sales"))
.movingAverage(7)
}.toPoints()
```

## Admin Bypass

Admin users automatically bypass all RLS policies:

```swift
let admin = BlazeUserContext.admin()
let points = try db.graph(for: admin) {
 $0.x("category")
.y(.count)
}.toPoints()

// Admin sees ALL records, regardless of policies
```

## Examples

### Team-Based Access

```swift
// Setup
db.rls.enable()
db.rls.addPolicy(SecurityPolicy(
 name: "team_access",
 operation:.select,
 type:.restrictive
) { record, context in
 guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
 return context.teamIDs.contains(teamID)
})

// Query as engineer
let engineer = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])
let dailySales = try db.graph(for: engineer) {
 $0.x("createdAt",.day)
.y(.sum("amount"))
}.toPoints()

// Engineer sees only their team's sales
```

### Assigned Records Only

```swift
// Setup
db.rls.enable()
db.rls.addPolicy(SecurityPolicy(
 name: "assigned_access",
 operation:.select,
 type:.restrictive
) { record, context in
 guard let assignedTo = record.storage["assigned_to"]?.uuidValue else { return false }
 return assignedTo == context.userID
})

// Query as viewer
let viewer = BlazeUserContext.viewer(userID: userID)
let myTasks = try db.graph(for: viewer) {
 $0.x("status")
.y(.count)
}.toPoints()

// Viewer sees only assigned tasks
```

### Role-Based Access

```swift
// Setup: Engineers see team records, viewers see assigned records
db.rls.enable()
db.rls.addPolicy(SecurityPolicy(
 name: "role_based_access",
 operation:.select,
 type:.restrictive
) { record, context in
 if context.hasRole("engineer") {
 // Engineers see team records
 guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
 return context.teamIDs.contains(teamID)
 } else if context.hasRole("viewer") {
 // Viewers see assigned records
 guard let assignedTo = record.storage["assigned_to"]?.uuidValue else { return false }
 return assignedTo == context.userID
 }
 return false
})

// Query as engineer
let engineer = BlazeUserContext.engineer(userID: userID, teamIDs: [teamID])
let teamStats = try db.graph(for: engineer) {
 $0.x("category")
.y(.count)
}.toPoints()
```

## Protocol-Based Policies (Optional)

For type-safe policy definitions, you can use the `RLSPolicy` protocol:

```swift
struct BugRLSPolicy: RLSPolicy {
 typealias Model = Bug

 func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
 if user.isAdmin {
 return { _ in true } // Admin bypass
 }

 return { record in
 guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
 return user.isMemberOf(team: teamID)
 }
 }
}

// Register policy
BlazeRLSRegistry.registerRLS(Bug.self, policy: BugRLSPolicy())
```

### Built-in Policy Types

BlazeDB provides convenient policy implementations:

```swift
// Team-based policy
let teamPolicy = TeamBasedRLSPolicy<Bug>(teamIDField: "team_id")
BlazeRLSRegistry.registerRLS(Bug.self, policy: teamPolicy)

// Owner-based policy
let ownerPolicy = OwnerBasedRLSPolicy<Bug>(ownerIDField: "owner_id")
BlazeRLSRegistry.registerRLS(Bug.self, policy: ownerPolicy)

// Role-based policy
let rolePolicy = RoleBasedRLSPolicy<Bug>(
 teamIDField: "team_id",
 assignedToField: "assigned_to"
)
BlazeRLSRegistry.registerRLS(Bug.self, policy: rolePolicy)
```

## Filter Combination

RLS filters are combined with user filters using AND logic:

```
effectiveFilter = RLSFilter && UserFilter
```

This means:
- Records must pass RLS policy check
- AND records must pass user-defined filters

Example:
```swift
let points = try db.graph(for: userContext) {
 $0.x("status")
.y(.count)
.filter { $0.storage["priority"]?.intValue?? 0 > 5 }
}.toPoints()

// Only returns records that:
// 1. Pass RLS policy (user can access)
// 2. Have priority > 5 (user filter)
```

## Backward Compatibility

**RLS is completely optional.** If you don't configure it:

- Graph queries work exactly as before
- No performance overhead
- No behavior changes

```swift
// This works exactly as before (no RLS)
let points = try db.graph() {
 $0.x("category")
.y(.count)
}.toPoints()

// This also works (RLS not enabled)
let points = try db.graph(for: userContext) {
 $0.x("category")
.y(.count)
}.toPoints()
// (No filtering occurs if RLS is disabled)
```

## Performance Considerations

1. **RLS Filter Evaluation**: RLS filters are evaluated during query execution, not at query build time. This ensures policies are always up-to-date.

2. **Filter Order**: RLS filters are applied first, then user filters. This allows early filtering of inaccessible records.

3. **Admin Bypass**: Admin users skip RLS evaluation entirely, providing optimal performance.

4. **No Overhead When Disabled**: If RLS is disabled or no user context is provided, there is zero performance overhead.

## Limitations

1. **Policy Evaluation**: Policies are evaluated per-record during query execution. For very large datasets, consider pre-filtering or indexing.

2. **Context Management**: User context is captured at query creation time. If user permissions change, create a new query.

3. **Type Safety**: The protocol-based policy system is optional. You can use the existing `SecurityPolicy` system directly.

## Best Practices

1. **Enable RLS Only When Needed**: Only enable RLS if you have multi-user scenarios. For single-user apps, leave it disabled.

2. **Use Admin Sparingly**: Admin users bypass all security. Use only for system operations or debugging.

3. **Combine with Indexes**: For team-based access, ensure `team_id` fields are indexed for optimal performance.

4. **Test Policies**: Always test RLS policies with different user roles to ensure correct filtering.

5. **Document Policies**: Document your RLS policies clearly, especially for complex multi-role scenarios.

## See Also

- [Graph Query API](API/GRAPH_QUERY_API.md)
- [Security Documentation](Security/)
- [Query Builder API](API/QUERY_BUILDER_API.md)

