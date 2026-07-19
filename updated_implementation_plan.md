# Implementation Plan — RBAC + Google Sign-In Only

## Background
Replace email/password auth with **Google Sign-In only**. Implement 4 roles with strict UI gating.
New signups via Google → Firestore profile created with `role: 'viewer'`, `isCoreTeamMember: false`.
Admin must upgrade roles from the Admin Dashboard.

---

## Role Permissions Summary

| Feature | Admin | Collector | Collector + Team Member (Dual) | Team Member | Viewer |
|---|---|---|---|---|---|
| Create tags on map | ✅ | ✅ | ✅ | ❌ | ❌ |
| Collect funds (photo + amount) | ✅ | ✅ | ✅ | ❌ | ❌ |
| Edit / Reset collected data | ✅ only | ❌ | ❌ | ❌ | ❌ |
| View all tags (pending + uncollected + collected) | ✅ | ✅ | ✅ | ✅ | ❌ |
| View collected tags (with amount + image) | ✅ | ✅ | ✅ | ✅ | ✅ |
| AR View | ✅ | ✅ | ✅ | ❌ **completely hidden** | ❌ **completely hidden** |
| Reports section | ✅ Full | ✅ Own + Leaderboard | ✅ Full data | ✅ Full data | ❌ **completely hidden** |
| View all collectors' full data | ✅ | ❌ | ✅ | ✅ | ❌ |
| Admin Dashboard | ✅ only | ❌ | ❌ | ❌ | ❌ |
| Can be flagged as Dual Role | ❌ | ✅ (admin sets) | — | ❌ | ❌ |

> **Dual Role:** A `collector` with `isCoreTeamMember: true` retains full collector abilities AND gets team-level visibility in Reports.
> **Viewer:** Can only see collected tags + tap to see photo + amount. All other features hidden/blocked.

---

## Proposed Changes

### Phase 1 — Auth: Replace Email/Password with Google Sign-In

#### [MODIFY] [pubspec.yaml](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/pubspec.yaml)
Add dependency:
```yaml
google_sign_in: ^6.2.1
```

#### [MODIFY] [auth_service.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/services/auth_service.dart)
- **Remove** `signIn(email, password)` and `signUp(email, password, name)` methods entirely.
- **Add** `signInWithGoogle()` method:
  ```dart
  Future<auth.UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled
    final googleAuth = await googleUser.authentication;
    final credential = auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    // Create Firestore profile only on first sign-in
    final uid = userCredential.user!.uid;
    final doc = await _firestore.collection('collectors').doc(uid).get();
    if (!doc.exists) {
      await _firestore.collection('collectors').doc(uid).set({
        'name': userCredential.user!.displayName ?? 'Unknown',
        'email': userCredential.user!.email ?? '',
        'photoUrl': userCredential.user!.photoURL ?? '',
        'role': 'viewer',              // ← default role
        'isCoreTeamMember': false,
      });
    }
    return userCredential;
  }
  ```
- **Update** `signOut()` to also call `GoogleSignIn().signOut()`.
- **Add** `updateCollectorTeamStatus(String uid, bool isCoreTeamMember)`:
  ```dart
  Future<void> updateCollectorTeamStatus(String uid, bool isCoreTeamMember) async {
    await _firestore.collection('collectors').doc(uid).update({
      'isCoreTeamMember': isCoreTeamMember,
    });
  }
  ```
- Keep `updateCollectorRole()` — expand accepted values to: `'viewer'`, `'collector'`, `'team_member'`, `'admin'`.
  - When role changes away from `'collector'`, also reset `isCoreTeamMember: false`.

#### [MODIFY] [login_screen.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/screens/login_screen.dart)
- **Remove** all `TextFormField`s for name, email, password.
- **Remove** `_isLogin` toggle (no more signup vs login separation).
- **Replace** with a single clean screen:
  - App logo / name at top.
  - Single **"Sign in with Google"** button (white button with Google logo icon).
  - On press: calls `authService.signInWithGoogle()`.
  - Show `CircularProgressIndicator` while loading.
  - Show error `SnackBar` on failure.
  - Navigation handled automatically by `authStateProvider` in the router.

---

### Phase 2 — Model: Update Collector Schema

#### [MODIFY] [collector.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/models/collector.dart)
- Update `role` comment: supports `'admin'`, `'collector'`, `'team_member'`, `'viewer'`.
- Add `bool isCoreTeamMember` field (default `false`).
- Add `String? photoUrl` field (from Google profile).
- Update `fromMap`: `role` defaults to `'viewer'` (not `'collector'`).
- Update `toMap` to include `isCoreTeamMember` and `photoUrl`.
- Add computed helper getters:
  ```dart
  bool get isAdmin => role == 'admin';
  bool get isCollector => role == 'collector';
  bool get isTeamMember => role == 'team_member';
  bool get isViewer => role == 'viewer';
  bool get canCreate => isAdmin || isCollector;
  bool get canSeeAllTags => isAdmin || isCollector || isTeamMember || isCoreTeamMember;
  bool get canSeeTeamData => isAdmin || isTeamMember || isCoreTeamMember;
  bool get canAccessAR => isAdmin || isCollector;
  bool get canAccessReports => isAdmin || isCollector || isTeamMember;
  ```

---

### Phase 3 — Router: Add Role-Based Guards

#### [MODIFY] [app_router.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/router/app_router.dart)
- Watch `collectorProfileProvider` in the router provider.
- Add role redirect in the global `redirect` callback:
  ```dart
  final authState = ref.watch(authStateProvider);
  final profileAsync = ref.watch(collectorProfileProvider);
  final profile = profileAsync.value;

  // ... existing auth guard ...

  // Role-based guards (only run if authenticated)
  if (isAuth && profile != null) {
    final loc = state.matchedLocation;
    if (loc == '/ar' && !profile.canAccessAR) return '/';
    if (loc == '/reports' && !profile.canAccessReports) return '/';
    if (loc == '/admin' && !profile.isAdmin) return '/';
  }
  ```

---

### Phase 4 — Home Screen: Hide Icons by Role

#### [MODIFY] [home_screen.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/screens/home_screen.dart)

**AppBar actions (lines 68–92):** Replace hardcoded `isAdmin` check with full role helpers:
```dart
final profile = collectorAsync.value;
final isAdmin = profile?.isAdmin ?? false;
final canCreate = profile?.canCreate ?? false;
final canAccessAR = profile?.canAccessAR ?? false;
final canAccessReports = profile?.canAccessReports ?? false;
```
- Admin Dashboard icon: only if `isAdmin` ✅ (already done)
- Reports icon: only if `canAccessReports` (hide from viewer)
- AR icon: only if `canAccessAR` (hide from viewer + team_member)
- Logout icon: always visible

**"Tag Here" FAB (lines 131–152):** Wrap with `if (canCreate)` — hide entirely for viewer/team_member.

**2D Map markers `_buildMarkers` (lines 306–361):**
- Pass `canSeeAllTags` as a parameter.
- If `!canSeeAllTags` (viewer): filter to `building.collectedCount > 0` only.
- Filter chips: if viewer, show only `'All'` and `'Completed'` chips — hide `'Not Collected'` and `'Pending'`.

---

### Phase 5 — Building Dialogs: Role-Gated Actions

#### [MODIFY] [building_dialogs.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/utils/building_dialogs.dart)

**In `showCollectionBottomSheet`:**

Read role helpers at the top of the function:
```dart
final profile = ref.read(collectorProfileProvider).value;
final isAdmin = profile?.isAdmin ?? false;
final canCreate = profile?.canCreate ?? false;
final isViewer = profile?.isViewer ?? false;
```

- **"Add Unit" button** (line 76–80 and 206–210): Change `onPressed` guard → only show if `canCreate`.
- **Relocate Tag + Delete Building** (already admin-gated ✅): No change needed.
- **Unit label Rename button** (line 133–165): Wrap with `if (isAdmin)` — hide from collectors/viewers/team_members.
- **Unit list filtering (multi-unit):** Before building the `ListView`, if `isViewer`, filter units: `final displayUnits = isViewer ? units.where((u) => u.status == 'collected').toList() : units;`
- **Unit `onTap`:** Already calls `showUnitAmountForm` → gating is handled inside `_buildAmountForm`.

**In `_buildAmountForm` (line 272+):**

Replace current `isAdmin` check with full role-based logic:
```dart
final profile = ref.read(collectorProfileProvider).value;
final isAdmin = profile?.isAdmin ?? false;
final canCreate = profile?.canCreate ?? false;
```

- **Pending unit + `!canCreate`** (viewer/team_member): Show a read-only placeholder:
  ```dart
  if (!isAlreadyCollected && !canCreate) {
    return _buildPendingPlaceholder(context, building, unit);
  }
  ```
  Placeholder shows: building name, unit label, a clock icon, "Pending Collection" label — no input fields.
- **Collected unit — EDIT/RESET buttons (line 431–474):** Keep `if (isAdmin)` — no change.
- **Rename unit pencil icon in header (lines 491–525):** Wrap with `if (isAdmin)` — collectors/viewers cannot rename.
- **Collected unit for non-admin, non-viewer:** Show photo + amount + collector name + date. No edit buttons (just the "Only admins can edit" note remains). ✅ Already correct.

---

### Phase 6 — Reports Screen: Role-Based Data

#### [MODIFY] [reports_screen.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/screens/reports_screen.dart)

> Route guard (Phase 3) already blocks viewers from reaching this screen.

In `initState` / `_loadCollections()`, read the profile and decide what to load:
```dart
void _loadCollections() {
  final profile = ref.read(collectorProfileProvider).value;
  final uid = ref.read(authStateProvider).value?.uid ?? '';
  final canSeeTeamData = profile?.canSeeTeamData ?? false;

  if (canSeeTeamData) {
    // Admin / Team Member / Dual Role: load everything
    _collectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections();
  } else {
    // Regular Collector: load only their own
    _collectionsFuture = ref.read(buildingServiceProvider).getMyCollections(uid);
  }
}
```

**Add leaderboard section for regular collectors:**
After the "Recent Collections" list, if `!canSeeTeamData`, show:
```
🏆 COLLECTOR LEADERBOARD
  1. Rajesh Kumar    ₹ 45,200
  2. Suresh M        ₹ 38,100
  3. [current user]  ₹ 31,500  ← highlighted
```
Each row shows: rank, name, total amount only. No entry details for others.

---

### Phase 7 — Building Service: New Methods

#### [MODIFY] [building_service.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/services/building_service.dart)

**Add `getMyCollections(String uid)`:**
- Same as `getDetailedCollections()` but adds `.where('collectedBy', isEqualTo: uid)` filter on units query.
- Returns `List<Map<String, dynamic>>` with `{'unit': Unit, 'building': Building}`.

**Add `getCollectorLeaderboard()`:**
- Fetch all collectors from Firestore `collectors` collection.
- Fetch all collected units across all buildings.
- Group by `collectedBy` uid, sum `amount`.
- Return `List<Map<String, dynamic>>` with `{'uid': string, 'name': string, 'total': double}` sorted descending by total.

---

### Phase 8 — Admin Dashboard: 4-Role Management

#### [MODIFY] [admin_screen.dart](file:///C:/Users/HP/Documents/Projects/Ganesha%20Funds%20Tracker/lib/screens/admin_screen.dart)

**In `_TeamTab` (lines 41–93):**

Expand role `DropdownButton` values (line 73–76):
```dart
items: const [
  DropdownMenuItem(value: 'viewer',      child: Text('Viewer')),
  DropdownMenuItem(value: 'collector',   child: Text('Collector')),
  DropdownMenuItem(value: 'team_member', child: Text('Team Member')),
  DropdownMenuItem(value: 'admin',       child: Text('Admin')),
],
```

When role changes away from `'collector'`, also reset `isCoreTeamMember: false`.

**Add "Core Team Member" toggle below each ListTile** where `collector.role == 'collector'`:
```dart
if (collector.role == 'collector')
  SwitchListTile(
    title: const Text('Also a Core Team Member'),
    subtitle: const Text('Sees team-level reports data'),
    value: collector.isCoreTeamMember,
    onChanged: (val) async {
      await authService.updateCollectorTeamStatus(collector.id, val);
    },
  ),
```

**Show Google profile photo** in `CircleAvatar` if `collector.photoUrl` is available:
```dart
leading: CircleAvatar(
  backgroundImage: collector.photoUrl != null 
      ? NetworkImage(collector.photoUrl!) 
      : null,
  child: collector.photoUrl == null 
      ? Text(collector.name[0].toUpperCase()) 
      : null,
),
```

---

## Verification Plan

1. **Google Sign-In**: Tap "Sign in with Google" → Google account picker appears → after sign-in, Firestore `collectors/{uid}` created with `role: 'viewer'`, `isCoreTeamMember: false`.
2. **Viewer**: Reports icon absent. AR icon absent. "Tag Here" FAB absent. Map shows green pins only. Tap collected tag → see photo + amount.
3. **Team Member**: Reports icon visible (full data). AR icon absent. "Tag Here" FAB absent. All pins visible.
4. **Collector**: Reports icon visible (own data + leaderboard). AR icon visible. "Tag Here" FAB visible. Cannot edit collected units.
5. **Dual Role Collector (`isCoreTeamMember: true`)**: Same as collector + sees full team data in Reports.
6. **Admin Dashboard**:
   - Role dropdown has 4 options.
   - For `collector` rows: "Core Team Member" toggle shown.
   - For `team_member`/`viewer`/`admin` rows: toggle hidden.
   - Changing collector's role to anything else → `isCoreTeamMember` resets to false.
7. **Route guards**: Navigating to `/ar` as viewer/team_member → silently redirected to `/`. Same for `/reports` as viewer.
