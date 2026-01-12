# Chat Final Fixes - Context, History & Typing Indicator

## Problems Identified

1. ❌ **No context sent to GPT** - Only alert_state_id and message (makes GPT generic)
2. ❌ **No conversation history** - Each message is stateless
3. ❌ **No typing indicator** - User doesn't know AI is responding
4. ❌ **Alarmist opening messages** - "This is serious and requires immediate action" is too medical

---

## Fix 1: Send Context & History

### Swift Changes (DashboardNotifications.swift)

Add these helper functions before `sendMessage`:

```swift
private func buildChatContextPayload() -> [String: Any] {
    // Build comprehensive context for GPT
    var context: [String: Any] = [
        "member_name": item.memberName,
        "pillar": item.pillar.rawValue,
        "alert_headline": item.title,
        "severity": severityLabel,
        "duration_days": parseDuration(from: item.debugWhy)
    ]
    
    // Add available metrics data
    if !dailyData.isEmpty {
        let recentData = Array(dailyData.suffix(14)).map { day in
            [
                "date": day.date,
                "value": day.value as Any? ?? NSNull()  // null, not 0
            ]
        }
        context["recent_daily_values"] = recentData
    }
    
    // Add optimal range if available
    if let optMin = optimalTarget?.min, let optMax = optimalTarget?.max {
        context["optimal_range"] = [
            "min": optMin,
            "max": optMax
        ]
    }
    
    // Add AI insight if available
    if let headline = aiInsightHeadline {
        context["ai_insight_headline"] = headline
    }
    if let clinical = aiInsightClinicalInterpretation {
        context["clinical_interpretation"] = clinical
    }
    if let connections = aiInsightDataConnections {
        context["data_connections"] = connections
    }
    
    return context
}

private func buildChatHistoryPayload() -> [[String: String]] {
    // Send last 10 messages for conversation context
    return Array(chatMessages.suffix(10)).map { msg in
        [
            "role": msg.role == .miya ? "assistant" : "user",
            "text": msg.text
        ]
    }
}
```

### Update sendMessage request body:

```swift
req.httpBody = try JSONSerialization.data(withJSONObject: [
    "alert_state_id": alertId,
    "message": trimmedText,
    "context": buildChatContextPayload(),  // ✅ Add context
    "history": buildChatHistoryPayload()   // ✅ Add history
])
```

---

## Fix 2: Update Edge Function to Use Context & History

### Edge Function Changes (miya_insight_chat/index.ts)

Update the body type and handling:

```typescript
const body = await req.json().catch(() => null) as { 
  alert_state_id?: string; 
  message?: string;
  context?: any;      // ✅ Accept context
  history?: any[];    // ✅ Accept history
} | null;

const alertStateId = body?.alert_state_id;
const message = (body?.message ?? "").trim();
const clientContext = body?.context || {};       // ✅ Get context
const clientHistory = body?.history || [];       // ✅ Get history
```

Use client context if provided, otherwise fall back to fetching:

```typescript
// Use client-provided context if available (more efficient)
let healthInsight;
let memberName;

if (clientContext && Object.keys(clientContext).length > 0) {
  // Client sent context - use it directly
  memberName = clientContext.member_name?.split(" ")[0] || "the family member";
  
  healthInsight = {
    member: { name: memberName },
    timeframe: `last ${clientContext.duration_days || 'several'} days`,
    alert: clientContext.alert_headline || cached.headline,
    keyFindings: [
      ...(clientContext.clinical_interpretation ? [clientContext.clinical_interpretation] : []),
      ...(clientContext.data_connections ? [clientContext.data_connections] : []),
    ].filter(Boolean),
    recentValues: clientContext.recent_daily_values || [],
    optimalRange: clientContext.optimal_range || null,
    caveats: []
  };
} else {
  // Fall back to fetching from database (old behavior)
  memberName = ((cached.evidence as any)?.person?.name ?? "").split(" ")[0] || "the family member";
  // ... existing database fetch logic ...
}
```

Use client history if provided:

```typescript
// Use client-provided history if available
const chatMessages: Array<{ role: "user" | "assistant"; content: string }> = 
  clientHistory.length > 0 
    ? clientHistory.map((m: any) => ({ 
        role: m.role === "assistant" ? "assistant" : "user", 
        content: m.text 
      }))
    : (msgs ?? []).map((m: any) => ({ role: m.role, content: m.content }));
```

---

## Fix 3: Animated Typing Indicator

### Add Loading State

In your `@State` variables, add:

```swift
@State private var isAITyping = false  // ✅ New state
```

### Update sendMessage to show typing:

```swift
await MainActor.run {
    inputText = ""
    if !skipAddingUserMessage {
        chatMessages.append(ChatMessage(role: .user, text: trimmedText))
        retryCount = 0
    }
    isSending = true
    isAITyping = true  // ✅ Show typing indicator
    chatError = nil
}
```

After receiving response:

```swift
await MainActor.run {
    isAITyping = false  // ✅ Hide typing indicator
    chatMessages.append(ChatMessage(role: .miya, text: reply))
    isSending = false
    // ...
}
```

On error:

```swift
await MainActor.run {
    isAITyping = false  // ✅ Hide typing indicator
    chatError = "..."
    isSending = false
}
```

### Add Typing Indicator UI

In your chat message list, after the last message:

```swift
ForEach(chatMessages) { message in
    // ... existing message bubbles ...
}

// ✅ Add typing indicator
if isAITyping {
    HStack(spacing: 12) {
        Circle()
            .fill(Color("MiyaPurple").opacity(0.3))
            .frame(width: 32, height: 32)
            .overlay(
                Text("M")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color("MiyaPurple"))
            )
        
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAITyping ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAITyping
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(20)
        
        Spacer()
    }
    .padding(.horizontal)
    .transition(.opacity)
}
```

---

## Fix 4: Tone Down Alarmist Opening Messages

### Replace "serious" language:

```swift
// 21+ day patterns (urgent/severe)
case (15..., _):
    return "Hey — \(firstName)'s \(metricName) has been below baseline for \(duration) days. This pattern has been going on for a while and needs your attention. Let's figure out what's happening and how to best support \(firstName)."
```

Change from:
> "This is serious and requires immediate action. We need to talk about what's happening and get \(firstName) the support they need right away."

To:
> "This pattern has been going on for a while and needs your attention. Let's figure out what's happening and how to best support \(firstName)."

**Why**: Avoids sounding like a medical emergency while still conveying urgency.

---

## Summary of Changes

| Component | Change | Impact |
|-----------|--------|--------|
| **Swift Request** | Add `context` and `history` | GPT gets full context every turn |
| **Edge Function** | Accept and use `context` + `history` | Less DB queries, better responses |
| **Typing Indicator** | Add animated dots | User knows AI is working |
| **Opening Messages** | Remove "serious"/"immediate action" | Less alarmist, more supportive |

---

## Testing Checklist

After implementing:

- [ ] Send a chat message → see animated typing indicator
- [ ] GPT should reference specific data points from context
- [ ] Multi-turn conversation should remember previous messages
- [ ] Opening message should feel supportive, not scary
- [ ] Response should be grounded in the data you sent

---

## Why This Matters

**Before**:
- GPT is blind (only knows alert ID)
- Every message is stateless
- User sees nothing while waiting
- Opening sounds like a medical emergency

**After**:
- GPT has full health context + history
- Conversation has memory
- User sees "AI is typing..."
- Opening is supportive and actionable

This transforms the chat from a generic bot to a knowledgeable coach who actually understands the situation.
