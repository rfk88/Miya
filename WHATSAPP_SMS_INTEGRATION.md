# WhatsApp & SMS Deep Link Integration

## Overview
Implemented direct deep links to open WhatsApp and Messages apps with pre-filled text, eliminating the need for users to manually copy/paste messages.

## What Changed

### 1. Added URL Scheme Helper Functions
**File:** `Miya Health/DashboardView.swift`

Added two private methods to `FamilyNotificationDetailSheet`:

**`openWhatsApp(with message: String)`**
- Uses WhatsApp's URL scheme: `whatsapp://send?text=`
- Encodes the message for URL safety
- Checks if WhatsApp is installed before opening
- Falls back to App Store if not installed

**`openMessages(with message: String, phoneNumber: String? = nil)`**
- Uses iOS SMS URL scheme: `sms:&body=`
- Supports optional phone number parameter (for future enhancement)
- Encodes the message for URL safety
- Opens the native Messages app

### 2. Updated "Reach Out" Section UI

**Before:**
- Single button: "Share via WhatsApp, Text, etc."
- Opened generic iOS share sheet
- User had to select app and paste

**After:**
- **"Send via WhatsApp"** button (WhatsApp green #26C95F)
  - Icon: message.fill
  - Opens WhatsApp directly with message pre-filled
  
- **"Send via Text Message"** button (Green)
  - Icon: message.badge.fill
  - Opens Messages app directly with message pre-filled
  
- **"More Options..."** button (Gray)
  - Icon: square.and.arrow.up
  - Opens standard iOS share sheet as fallback
  - Gives access to other apps (email, Slack, etc.)

## How It Works

### User Flow

1. **User taps on family member notification**
2. **Views AI insight and suggested messages**
3. **Selects message template** (e.g., "Gentle encouragement")
4. **Taps "Send via WhatsApp"** → WhatsApp opens instantly with message ready
   - Or taps "Send via Text Message" → Messages app opens
   - Or taps "More Options" → Standard share sheet

### Technical Flow

```
User taps WhatsApp button
    ↓
openWhatsApp(with: message) called
    ↓
URL encode the message
    ↓
Build URL: "whatsapp://send?text=<encoded_message>"
    ↓
Check if WhatsApp is installed (canOpenURL)
    ↓
    ├─ YES → Open WhatsApp with message
    └─ NO → Open App Store to install WhatsApp
```

## URL Schemes Used

### WhatsApp
- **Basic:** `whatsapp://send?text=Hello%20World`
- **With phone:** `whatsapp://send?phone=+1234567890&text=Hello`
- **Universal link:** `https://wa.me/?text=Hello` (works without app)

### Messages/SMS
- **Basic:** `sms:&body=Hello%20World`
- **With recipient:** `sms:+1234567890&body=Hello`

## Benefits

✅ **One-tap sharing** - No extra steps
✅ **Pre-filled messages** - No copy/paste needed
✅ **User-friendly** - Instant feedback
✅ **Smart fallbacks** - Handles app not installed
✅ **Flexible** - Still have "More Options" for other apps
✅ **Native experience** - Uses iOS URL schemes

## Future Enhancements

### 1. Phone Number Integration
If you store family member phone numbers in the database:

```swift
// Fetch from user_profiles or family_members table
@State private var memberPhoneNumber: String? = nil

// Use it
Button {
    openMessages(with: selectedShareText, phoneNumber: memberPhoneNumber)
} label: {
    // ... Send to [Member Name]
}
```

### 2. Other Apps
Can add similar buttons for:
- **Telegram:** `tg://msg?text=Hello`
- **Signal:** `sgnl://send?text=Hello`
- **iMessage:** Same as SMS, iOS detects iMessage availability

### 3. Deep Link to Specific Contact
WhatsApp supports direct contact links if you have their phone:
```swift
"whatsapp://send?phone=+1234567890&text=Hello"
```

### 4. Track Which Method Users Prefer
Add analytics to see if users prefer WhatsApp vs SMS:
```swift
Button {
    // Track analytics
    Analytics.track("share_method", properties: ["type": "whatsapp"])
    openWhatsApp(with: selectedShareText)
} label: { ... }
```

## Testing Instructions

### Test WhatsApp Integration
1. **With WhatsApp installed:**
   - Rebuild app in Xcode (Cmd+B)
   - Open a family member's health notification
   - Tap "Send via WhatsApp"
   - **Expected:** WhatsApp opens with message pre-filled
   - **Verify:** Message content is correct

2. **Without WhatsApp installed:**
   - Delete WhatsApp from device
   - Tap "Send via WhatsApp"
   - **Expected:** App Store opens to WhatsApp page

### Test Messages Integration
1. Rebuild app
2. Open health notification
3. Tap "Send via Text Message"
4. **Expected:** Messages app opens with message pre-filled
5. **Verify:** Message content is correct

### Test Fallback
1. Tap "More Options..."
2. **Expected:** Standard iOS share sheet appears
3. **Verify:** Can share to other apps (Mail, Notes, etc.)

## Code Locations

**Helper Functions:**
- Lines ~7112-7140 in `DashboardView.swift`

**UI Implementation:**
- Lines ~6283-6350 in `DashboardView.swift`
- Inside `FamilyNotificationDetailSheet` → "Reach Out" section

## Notes

- URL encoding automatically handles special characters
- iOS handles the actual opening of apps - we just provide the URL
- If app isn't installed, iOS shows error or opens App Store
- No additional permissions needed - URL schemes are standard iOS feature
- Works on iOS 10+ (all devices you support)

## Edge Cases Handled

✅ **App not installed:** Falls back to App Store
✅ **Special characters in message:** URL encoded automatically
✅ **Long messages:** URL encoding handles all lengths
✅ **User cancels:** No action taken, they stay in Miya
✅ **Network issues:** Doesn't matter - just opens the app locally

## Visual Design

All buttons follow Miya's design system:
- 12px corner radius
- 14px vertical padding, 20px horizontal
- Proper spacing (12px between buttons)
- Clear hierarchy (WhatsApp → SMS → More Options)
- Accessibility-friendly tap targets
- Color-coded for quick recognition

Ready to test! 🚀
