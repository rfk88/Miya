# Family Notifications – Single-Line Display Plan

---

## What We’re Doing (Overview)

We’re changing **all** family notifications so each one shows as a **single line** in the UI: **stat + name + baseline** where possible (e.g. **"28% below Rami's baseline"**), with the metric type shown by the icon. This applies to:

1. **Dashboard** – Family Notifications card (up to 3 items)
2. **See All** – All Notifications list (full list when user taps “See all”)

No more two-line title + body on the card; one line only, so cards stay compact and nothing is truncated mid-sentence.

---

## Where Notifications Come From (Data Sources)

Family notifications are built in three places:

| Source | Where | Example title | Example body |
|--------|--------|----------------|--------------|
| **Server pattern alerts** | [DashboardView+DataLoading.swift](Miya Health/Dashboard/DashboardView+DataLoading.swift) | "Movement below baseline" | "Movement is 28% below Rami's baseline (last 3d)." |
| **Trend insights** (local engine) | [NotificationModels.swift](Miya Health/Dashboard/NotificationModels.swift) build() from `TrendInsight` | "Rami · Sleep" | "Sleep has been in the lower range for 3 days. ..." |
| **Fallback** (no trends) | [NotificationModels.swift](Miya Health/Dashboard/NotificationModels.swift) build() | "Rami · Sleep" | "Sleep is the biggest drag on Rami's vitality..." |

We will **derive one display line** from the existing `title` and `body` so we don’t have to change every creation site. When the body already contains “X% below/above Name’s baseline”, we show that; otherwise we use the title as the single line.

---

## The Changes We Will Make

| Area | Current | After |
|------|--------|--------|
| **Model** | Card shows `item.title` + `item.body` (two lines) | Card shows `item.displayLine` (one line) |
| **displayLine** | N/A | New computed property on `FamilyNotificationItem`: stat + name + baseline when possible, else title |
| **Family Notifications card** | VStack with title (bold) + body | Single `Text(item.displayLine)` with `lineLimit(1)` |
| **All Notifications view** | VStack with title (bold) + body | Single `Text(notification.displayLine)` with `lineLimit(1)` |

**Files to edit**

1. **[Miya Health/Dashboard/NotificationModels.swift](Miya Health/Dashboard/NotificationModels.swift)** – Add `displayLine: String` computed property to `FamilyNotificationItem`.
2. **[Miya Health/Dashboard/FamilyNotificationsCard.swift](Miya Health/Dashboard/FamilyNotificationsCard.swift)** – In `notificationCard`, replace the two-line text block with one line using `item.displayLine`.
3. **[Miya Health/Dashboard/AllNotificationsView.swift](Miya Health/Dashboard/AllNotificationsView.swift)** – In `notificationCard`, replace the two-line text block with one line using `notification.displayLine`.

---

## Display-Line Rules (Computed Property)

**For `.trend(insight)`:**

- If `insight.body` contains the pattern like **" is 28% below Rami's baseline"** (i.e. “ is ” then a percentage then “ below ” or “ above ” then “ ’s baseline ”), extract that part and show **"28% below Rami's baseline"** (stat + direction + name + baseline). Same for “above”.
- If body contains “ (last ” (e.g. “ (last 3d). ”), strip that suffix when building the line so we don’t show “ (last 3d). ” in the one line.
- If we can’t extract that pattern (e.g. local trend bodies like “Sleep has been in the lower range…”), use **`insight.title`** as the single line (e.g. “Rami · Sleep” or “Movement below baseline”).

**For `.fallback(...)`:**

- Use **`title`** as the single line (e.g. “Rami · Sleep”).

So: **one line = “X% below/above Name’s baseline” when the body has that; otherwise one line = title.**

---

## Step-by-Step Execution

### Step 1: Add `displayLine` to `FamilyNotificationItem`

**File:** [Miya Health/Dashboard/NotificationModels.swift](Miya Health/Dashboard/NotificationModels.swift)

- Add a computed property `var displayLine: String` on `FamilyNotificationItem`.
- **Implementation:**
  - **`.fallback(..., title: title, body: body)`:** return `title`.
  - **`.trend(insight)`:**  
    - If `insight.body` contains `" is "` and (`" below "` or `" above "`) and `"'s baseline"`:
      - Find the substring after `" is "` (e.g. `"28% below Rami's baseline (last 3d)."`).
      - Remove a trailing part matching `" (last …"` (e.g. “ (last 3d).”) so the result is like `"28% below Rami's baseline"`.
      - Return that trimmed string.
    - Else: return `insight.title`.
- Keep `title` and `body` unchanged; they can still be used for chat, debug, or “See all” detail if needed later.

**Why:** One place defines the single-line format for every notification type; the UI only reads `displayLine`.

---

### Step 2: Family Notifications card – single line only

**File:** [Miya Health/Dashboard/FamilyNotificationsCard.swift](Miya Health/Dashboard/FamilyNotificationsCard.swift)

- In `notificationCard(_ item:)`, find the `VStack(alignment: .leading, spacing: 4)` that shows `Text(item.title)` and `Text(item.body)`.
- Replace that `VStack` with a single `Text(item.displayLine)`.
- Use one font style (e.g. the same as current body: size 14, regular, secondary color), and `.lineLimit(1)` so it stays one line. Optionally `.truncationMode(.tail)` so long lines show “…” at the end.

**Why:** Dashboard card shows only the one-line summary; no title + body.

---

### Step 3: All Notifications view – single line only

**File:** [Miya Health/Dashboard/AllNotificationsView.swift](Miya Health/Dashboard/AllNotificationsView.swift)

- In `notificationCard(notification:)`, find the `VStack(alignment: .leading, spacing: 4)` that shows `Text(notification.title)` and `Text(notification.body)`.
- Replace that `VStack` with a single `Text(notification.displayLine)`.
- Same styling as Step 2: one line, `.lineLimit(1)`, truncate tail if needed.

**Why:** “See all” list uses the same single-line format as the dashboard for consistency.

---

### Step 4: Verify

- Build and run.
- **Dashboard:** Confirm up to 3 notifications show one line each (e.g. “28% below Rami’s baseline” for server alerts; “Rami · Sleep” or “Movement below baseline” for others).
- **See all (4):** Open “See all” and confirm every notification shows one line only.
- **Chat / snooze:** Confirm tapping the card still opens chat and the snooze icon still works (no behavior change; only display changes).

---

## Summary

| Step | Action |
|------|--------|
| **1** | Add `displayLine: String` to `FamilyNotificationItem` in NotificationModels.swift (derive from body when “X% below/above Name’s baseline”, else title; fallback → title). |
| **2** | In FamilyNotificationsCard, replace title+body VStack with single `Text(item.displayLine)` and `lineLimit(1)`. |
| **3** | In AllNotificationsView, replace title+body VStack with single `Text(notification.displayLine)` and `lineLimit(1)`. |
| **4** | Build, run, and verify dashboard + See all + tap/snooze. |

After this, every family notification will show as a single line (stat + name + baseline where possible) on both the dashboard card and the “See all” list.
