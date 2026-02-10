# Family Notifications Card – Plan & Step-by-Step Execution

---

## What We’re Doing (Overview)

We’re fixing the Family Notifications section on the dashboard so that:

1. **No scrolling** – Up to 3 notification cards are always visible; the section never scrolls.
2. **Smaller cards** – Each card is shorter (smaller icon, less padding, tighter text) so three fit on screen.
3. **Tap = Chat** – Tapping anywhere on a notification card opens the chat for that notification.
4. **Snooze via icon** – A small snooze icon in the top-right of each card opens a confirmation: “Are you sure you want to snooze this?” Only after the user confirms do we snooze.

Today the section uses a scrollable **List** with tall rows, so the third card is cut off and users must scroll. We’re switching to a non-scrollable **VStack** with shorter cards and replacing swipe actions with tap-to-chat and a snooze icon + confirmation.

---

## The Changes We Will Make

| Area | Current | After |
|------|--------|--------|
| **Container** | `List` (scrollable), fixed height 90pt × 3 rows | `VStack` (no scroll), no fixed height – layout defines size |
| **Row modifiers** | `listRowInsets`, `listRowSeparator`, `listRowBackground` | Removed (only apply to List) |
| **Card size** | 52pt icon, 16pt padding, title/body 2 lines each | ~40pt icon, ~10–12pt padding, body can be 1 line to save height |
| **Open chat** | Swipe left → “Chat” | Tap on card → chat |
| **Snooze** | Swipe right → snooze immediately | Tap top-right snooze icon → alert “Are you sure?” → confirm → snooze |
| **Parameters** | `enableSwipeActions: Bool` passed in | Removed; no more swipe actions |

**Files to edit**

- **Miya Health/Dashboard/FamilyNotificationsCard.swift** – All layout and interaction changes.
- **Miya Health/DashboardView.swift** – Remove the `enableSwipeActions` argument when calling `FamilyNotificationsCard`.

---

## Step-by-Step Execution

### Step 1: Remove swipe actions and the `enableSwipeActions` parameter

**In `FamilyNotificationsCard.swift`:**

- Delete the `enableSwipeActions` property from the struct.
- In `notificationRow`, remove the `.if(enableSwipeActions) { ... }` wrapper and the entire `swipeActions` block. After this, `notificationRow` should simply return `notificationCard(item)` (we’ll add tap and snooze in later steps).

**In `DashboardView.swift`:**

- In the `FamilyNotificationsCard(...)` call, remove the line `enableSwipeActions: isServerMode,`.

**Why:** We’re replacing swipe with tap + snooze icon, so swipe and its parameter are no longer needed.

---

### Step 2: Replace the List with a VStack (no scrolling)

**In `FamilyNotificationsCard.swift`**, in the main `body`:

- Replace the `List { ForEach(displayedItems) { ... } }` block with a `VStack(spacing: 10)` (or similar) that contains the same `ForEach(displayedItems) { item in notificationRow(item) }`.
- Remove all modifiers that were on the List: `.listStyle(.plain)`, `.scrollContentBackground(.hidden)`, `.frame(height: CGFloat(displayedItems.count) * 90)`.
- Remove the `listRowInsets`, `listRowSeparator`, and `listRowBackground` modifiers from each row in the `ForEach`.

**Why:** A VStack doesn’t scroll, so all three cards will always be visible. The height will be determined by the content (three compact rows).

---

### Step 3: Shrink each notification card

**In `FamilyNotificationsCard.swift`**, inside `notificationCard`:

- **Icon circle:** Change `.frame(width: 52, height: 52)` to `.frame(width: 40, height: 40)`.
- **Icon font:** Change `.font(.system(size: 22, ...))` to `.font(.system(size: 18, ...))` (or 17 if 18 is too big).
- **Severity badge:** If the badge is still `offset(x: 18, y: -18)`, consider reducing to something like `offset(x: 14, y: -14)` so it stays proportional to the smaller circle.
- **Card padding:** Change `.padding(16)` to `.padding(12)` (or 10) so the card is shorter.
- **Text:** Optionally set body to `lineLimit(1)` and/or slightly reduce font size (e.g. body 13pt) so three rows fit comfortably. Keep title as is or at most 2 lines.

**Why:** Smaller icon and padding and tighter text reduce each row’s height so three rows fit without scrolling.

---

### Step 4: Make tapping the card open chat

**In `FamilyNotificationsCard.swift`:**

- We need the **card** to be tappable but **not** the snooze icon (so we add the snooze icon in Step 5 and keep it separate).
- In `notificationRow`, wrap the card in a `Button` that calls `onTap(item)`:
  - `Button { onTap(item) } label: { notificationCard(item) }`
  - Use `.buttonStyle(.plain)` or `NotificationCardButtonStyle()` so it doesn’t look like a default button.
- `notificationCard` will later get an overlay for the snooze icon; the button’s label should be the card **without** the snooze button, so the snooze icon is outside the button and won’t trigger chat. So: build the tappable card first (button with current `notificationCard`), then in Step 5 add the snooze icon as an overlay on the whole row so the icon is a separate control.

**Why:** One clear action: tap card → chat.

---

### Step 5: Add snooze icon and confirmation alert

**In `FamilyNotificationsCard.swift`:**

- Add state to drive the confirmation alert, e.g. `@State private var itemToSnooze: FamilyNotificationItem?`.
- **Snooze icon:** Add a small button (e.g. `Image(systemName: "bell.slash.fill")` or `"bell.slash"`) in the **top-right** of each notification row. Do this by:
  - Having `notificationRow` return a view that stacks/overlays the tappable card with a top-right snooze button (e.g. `ZStack(alignment: .topTrailing)` or overlay with alignment). The snooze button should **not** be inside the `Button` that triggers chat.
  - On snooze button tap: set `itemToSnooze = item` (do not call `onSnooze` yet).
- **Alert:** Attach an `.alert` to the card (or the row) that shows when `itemToSnooze != nil`:
  - Title/message: e.g. “Are you sure you want to snooze this?”
  - **Cancel:** set `itemToSnooze = nil` and dismiss.
  - **Confirm:** call `onSnooze(itemToSnooze!, defaultSnoozeDays(for: itemToSnooze!))`, then set `itemToSnooze = nil`.

Use a single `itemToSnooze` so only one confirmation is shown at a time.

**Why:** Snooze is a secondary action and easy to hit by mistake; confirmation prevents accidental snoozes.

---

### Step 6: Verify and tidy

- Build and run. Confirm:
  - Up to 3 notifications show without scrolling.
  - Tapping a card opens chat.
  - Tapping the snooze icon shows “Are you sure you want to snooze this?”; Cancel dismisses, Confirm snoozes.
- Remove any unused code (e.g. the private `if` modifier if it’s no longer used elsewhere in this file).
- In **DashboardView.swift**, ensure the only change is removal of `enableSwipeActions: isServerMode`.

---

## Summary

1. **Step 1:** Remove swipe actions and `enableSwipeActions` (card + DashboardView).
2. **Step 2:** Replace List with VStack; drop List-only and row modifiers.
3. **Step 3:** Shrink cards (icon 52→40, padding 16→12, optional text/line limits).
4. **Step 4:** Wrap card in Button → `onTap(item)` for chat.
5. **Step 5:** Add top-right snooze icon and “Are you sure?” alert; on confirm call `onSnooze`.
6. **Step 6:** Build, test, and clean up.

After this, the Family Notifications section will always show up to three compact cards, tap will open chat, and snooze will require a deliberate tap on the icon and a confirmation.
