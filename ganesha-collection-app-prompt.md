# Build Prompt for Antigravity IDE — Ganesha Festival Fund Collection App

> Paste this whole file into a new Antigravity conversation (Planning mode recommended), or paste it section by section if you want to review each Implementation Plan before it moves to the next part.

---

## 1. Project Overview

Build a mobile app called **"Ganesh Chanda Tracker"** for a small volunteer team collecting Ganesha festival donations door-to-door in a local neighborhood.

The core problem it solves: the team currently has no way to know which houses/shops have already been visited, who visited them, and how much was collected — this app fixes that with a shared, live-updating map.

Build this as a **Flutter app** targeting **Android, iOS, and Web** with **Firebase** as the backend (Firestore for data, Firebase Auth for team login, Firebase Storage for photos).

Do not use Google Maps or any paid mapping API. Use **OpenStreetMap tiles via the `flutter_map` package** for the map layer, since this app has zero budget for API costs.

---

## 2. Tech Stack — Be Explicit

- Framework: Flutter (latest stable), Dart.
- Backend: Firebase — Firestore (database), Firebase Auth (email/password login for team members only, no public signup), Firebase Storage (house photos).
- Map: `flutter_map` package with OpenStreetMap tile layer. No Google Maps SDK.
- Location: `geolocator` package for GPS and `flutter_compass` package for compass heading.
- Camera: `camera` package for the AR-lite overlay screen.
- State management: Riverpod. Use `StreamProvider` for the live Firestore-driven map pins and AR overlay data, and a simple provider for the current user's role.

---

## 2a. Platform Targets

- **Map screen, Login screen, Reports screen, and Admin screen** must work fully on Web — these only need standard browser APIs and are genuinely useful on a laptop, especially the Admin dashboard for reviewing reports on a bigger screen.
- **The Street View (AR-lite) screen is mobile-only (Android/iOS).** Do not build the camera-plus-compass overlay for Web — browser compass/heading support is unreliable and inconsistent across devices, and this feature depends on accurate continuous heading data. On Web builds, replace this screen with a simple message: "Street View is available in the mobile app — please use the Android or iOS app for this feature."
- Use `kIsWeb` (Flutter's built-in web-detection constant) to conditionally hide the Street View navigation entry point on Web builds.

---

## 3. Data Model — Implement Exactly This

Create this Firestore structure:

```
buildings/{buildingId}
  - lat: number
  - lng: number
  - name: string                 // "Shreeji Apartments" or "Sharma House"
  - type: string                 // "house" | "shop" | "apartment"
  - totalUnits: number           // 1 for a single house/shop
  - collectedCount: number       // derived, updates when units change
  - totalCollected: number       // derived sum of unit amounts
  - createdBy: string            // collector's user id
  - createdAt: timestamp

buildings/{buildingId}/units/{unitId}
  - unitLabel: string            // "A-101" or "Ground Floor" or just "Main" for a single house
  - status: string                // "pending" | "collected"
  - amount: number
  - collectedBy: string           // collector's user id
  - collectedAt: timestamp
  - photoUrl: string | null

collectors/{userId}
  - name: string
  - phone: string
  - assignedArea: string | null
```

Important rule: every building always has at least one unit inside it, even a single house — a plain house is just a building with `totalUnits: 1`. This keeps the data model consistent for both houses and apartments.

---

## 4. Screen 1 — Map Screen (Home)

Build the home screen as a full-screen map using `flutter_map` centered on the team's current GPS location on first load.

Show one pin per building, pulled live from Firestore (use a real-time `snapshots()` listener, not a one-time fetch, so all team members see updates instantly).

Color-code each pin based on collection progress:
- Red = 0 units collected
- Yellow = some units collected, not all — show a small badge on the pin with "collected/total", like "5/12"
- Green = all units collected

Tapping a pin opens a bottom sheet:
- If `totalUnits == 1`, show the amount-entry form directly (amount field, "Mark Collected" button, optional photo capture button).
- If `totalUnits > 1`, show a scrollable checklist of units, each row showing unit label and status, tapping a row opens the same amount-entry form for that specific unit.

Long-pressing anywhere on the map creates a new building pin at that location:
- Show a dialog asking for building name/landmark note, and a toggle "This is an apartment/building with multiple units" — if toggled on, ask how many units to pre-create (or allow adding units one at a time later), if off, create it as a single-unit house.

---

## 5. Screen 2 — Street View (AR-lite) Screen

Build a second screen accessible from the map screen via a button labeled "Street View".

This screen opens the phone's live camera feed as the background (using the `camera` package).

On top of the camera feed, overlay floating tags for nearby buildings using this logic:
1. Get the device's current GPS position (`geolocator`) and compass heading (`flutter_compass`), updating continuously.
2. For every building within roughly 100 meters, calculate the bearing from the device's current position to that building's lat/lng.
3. If the bearing is within about 30 degrees of the device's current compass heading (meaning the user is roughly facing that direction), draw a floating tag on screen at a horizontal position proportional to the angle offset (bearing minus heading, mapped to screen width).
4. The floating tag should show: building name, color-coded status (same red/yellow/green as the map pin), and progress badge — for example "Shreeji Apartments — 5/12 · ₹3,500".
5. Tapping a floating tag opens the same bottom sheet used on the map screen (unit checklist or amount-entry form).

This does not need to be pixel-perfect AR anchoring — it's a GPS-and-compass-based approximation. Do not attempt to use ARCore, Geospatial API, or any AR anchor SDK — keep it to the camera-feed-plus-overlay approach described above.

---

## 6. Screen 3 — Team Login

Simple email/password login screen using Firebase Auth. No public signup flow — assume team accounts are created manually by the app owner via the Firebase console. After login, store the logged-in collector's name/id so it can be attached to every collection entry.

---

## 7. Screen 4 — Reports

Build a simple reports screen showing:
- Total amount collected so far, across all buildings.
- A list of buildings sorted by status (pending first, then partial, then collected).
- A per-collector breakdown: how much each team member has collected.
- A button to export this summary as a CSV file (use the `csv` and `path_provider` packages, save to device storage, and show a share sheet using the `share_plus` package).

---

## 8. Role-Based Access Control — Critical, Do Not Skip

Fund manipulation is the biggest risk in this app, so access control must be enforced in **Firestore Security Rules**, not just hidden in the UI. The app UI can guide normal use, but the security rules are what actually stop someone from tampering with data even if they bypass the app.

### Roles

Add a `role` field to the `collectors/{userId}` document: `"admin"` or `"collector"`. Only an Admin can set or change this field — a new collector document defaults to `"collector"` and must be manually promoted in the Firebase console or by an existing Admin from within the app.

### Permission rules to implement

- **Collectors can:**
  - Create a new building/unit.
  - Set a unit's status from `"pending"` to `"collected"` exactly once, writing `amount`, `collectedBy` (must equal their own auth uid — never trust a client-sent uid), and `collectedAt` (use `serverTimestamp()`, never a client-sent time).
  - View all buildings/units on the map (they need this to avoid duplicate visits) but should NOT see the reports screen's collector-wise money breakdown — only Admins see who collected how much overall.

- **Collectors cannot:**
  - Edit `amount`, `status`, or `collectedBy` on a unit that is already `"collected"` — once written, those fields are locked for that role. Firestore rules should explicitly reject any update to a document where `resource.data.status == "collected"` unless the requester's role is `"admin"`.
  - Delete any building or unit document.
  - Change any other collector's role or profile.

- **Admins can:**
  - Do everything a collector can.
  - Edit or correct any unit's amount/status — but every such change must also write an entry to a new `corrections/{correctionId}` collection recording: `unitPath`, `fieldChanged`, `oldValue`, `newValue`, `changedBy`, `changedAt`, `reason`. Implement this as a single batched write so the correction and the update always happen together.
  - Delete buildings/units (soft-delete preferred: set a `deleted: true` flag rather than hard-deleting, so nothing is ever truly lost).
  - View the full reports screen, including collector-wise totals and the corrections log.
  - Promote/demote a collector's role.

### Implementation notes for Antigravity

- Write actual Firestore Security Rules code (not just app-side checks) implementing the permissions above. Use `get(/databases/$(database)/documents/collectors/$(request.auth.uid)).data.role` inside the rules to check the caller's role server-side.
- In the app, still hide/disable buttons a collector shouldn't use (better UX), but treat that as a convenience layer only — the security rules are the real enforcement and must work even if the UI is bypassed.
- Add a simple Admin-only screen: collector list with role toggle, and a corrections log viewer.
- The Map screen and Street View (AR-lite) screen described in Sections 4 and 5 are available to BOTH roles — collectors need these as their primary field tools. Do not gate either screen behind an Admin check. The only difference inside those screens is that tapping an already-`"collected"` pin/tag opens an editable correction form for Admins, but for Collectors it opens a read-only detail view (no edit fields).

## 9. Non-Functional Requirements

- The app must work with intermittent internet — queue writes locally and sync when connectivity returns (Firestore's offline persistence handles most of this automatically; make sure it's enabled).
- Keep the UI simple and large-tap-target — collectors will be using this quickly while standing at doorsteps, often in bright sunlight.
- No public-facing features, no payment processing inside the app — this only records that cash/UPI was collected offline, it does not process any transaction itself.

---

## 10. Build Order — Follow This Sequence

Please build and verify each part in this order before moving to the next, and show me the Implementation Plan for each part before starting:

1. Firebase project setup + Auth + login screen + `collectors` collection with `role` field.
2. Firestore Security Rules implementing the role-based permissions in Section 8 — get this reviewed and correct before building any screens that write data.
3. Firestore data model + map screen with live pins (single-unit houses only first).
4. Add multi-unit/apartment support (the unit checklist flow).
5. Add photo capture on collection entries.
6. Build the Street View (AR-lite) screen.
7. Build the Reports screen with CSV export, respecting the Admin-only visibility rules.
8. Build the Admin screen (collector role management + corrections log viewer).

Confirm the plan for step 1 with me before writing any code.