# Chat Guardrails & Formatting - Final Update

## Deployment Status ✅

| Function | Version | Status | Updated |
|----------|---------|--------|---------|
| `miya_insight` | 20 | ✅ ACTIVE | 2026-01-18 01:14:07 UTC |
| `miya_insight_chat` | 15 | ✅ ACTIVE | 2026-01-18 01:19:55 UTC |
| `rook` (with pre-warming) | 27 | ✅ ACTIVE | 2026-01-18 00:50:26 UTC |

**All functions are deployed and up to date.**

---

## New Guardrails Added

### 1. **Length Limits (No Walls of Text)**

**Rules enforced**:
- MAX 2-3 short paragraphs per response
- MAX 5-6 sentences total
- If listing items, use bullets (3-4 items max)
- This is a chat conversation, not a report

**Example enforcement**:
```
"RESPONSE LENGTH (STRICT):",
"- Keep responses SHORT and conversational - 2-3 short paragraphs MAX",
"- No massive text blocks or walls of text",
"- If multiple points, use bullets (3-4 items max)",
"- Remember: this is a chat conversation, not a report"
```

### 2. **Clean Formatting Guidelines**

**Markdown usage**:
- **Bold**: 1-2 key metrics or important terms per response
- Bullets: When listing 2+ items (max 3-4 items)
- Paragraphs: Break up any response longer than 3 sentences

**Example**:
```
📊 Based on the last 9 days, **Gulmira's sleep** dropped from 7.7 to 6.4 hours.

When sleep dips like this, it can affect energy and mood. Their **step count** also dropped 62.8%.

Has anything changed in their routine lately?
```

### 3. **Emoji Guidelines (Balanced, Not Overused)**

**Allowed**: 1-2 emojis per response maximum

**Emoji palette**:
- 😴 Sleep-related
- 🚶 🏃 Activity/steps
- 💓 Heart metrics
- 📊 Data/trends
- 💪 Recovery/strength
- 🎯 Goals/targets

**Rules**:
- Place naturally in context
- NOT at the start of every sentence
- NOT multiple emojis per line
- Use to add warmth, not clutter

**Good example**:
> "📊 Based on the last 9 days, **Gulmira's sleep** dropped..."

**Bad example** (emoji spam):
> "😴 Sleep 💤 has 📊 decreased 📉 significantly 🔻 over 📅 the last ⏰ 9 days 🌙"

### 4. **Conversational Structure**

Every response follows this pattern:

1. **Direct answer** with specific data (1-2 sentences)
2. **Brief context** or interpretation (2-3 sentences)
3. **Bullets** if listing multiple factors (3-4 max)
4. **One follow-up** question or suggestion

**Example**:
```
📊 Based on 9 days, **Gulmira's sleep** dropped from 7.7 to 6.4 hours - about 76 fewer minutes per night.

When sleep dips like this, it can affect energy and mood. Their **step count** also dropped 62.8%, meaning they're moving a lot less.

Common causes:
• Physical recovery or illness
• Increased stress levels
• Routine changes

Has anything changed in their daily routine recently?
```

---

## Response Length Comparison

### ❌ Bad (Wall of Text - Old Style)

> "The pattern is a sustained 38.9% decrease in daily steps over 9 consecutive days. This drop from about 7025 to 4294 steps may indicate injury, illness, lifestyle disruption, or changes in mental health and motivation. Additionally, we're seeing a corresponding decrease in sleep duration from 7.7 hours to 6.4 hours, representing approximately 76 fewer minutes per night. When both metrics decline simultaneously, it often suggests a systemic issue rather than isolated changes. Common causes include physical limitations affecting mobility, acute or chronic illness requiring additional rest, major routine disruptions such as weather changes or work schedule modifications, mental health factors including low motivation or depressive symptoms, or intentional rest periods. I recommend monitoring for additional symptoms, having a direct conversation about how they're feeling, and considering medical consultation if the pattern persists beyond two weeks without clear explanation."

**Problems**: 
- 8+ sentences without breaks
- No formatting
- Dense paragraph
- Reads like a clinical report

### ✅ Good (Conversational - New Style)

> "📊 Based on the last 9 days, **Gulmira's steps** dropped from 7,025 to 4,294 - about a 39% decrease. Their **sleep** also dipped from 7.7 to 6.4 hours per night.
> 
> When both activity and sleep drop together, it often points to:
> • Physical recovery or illness
> • Increased stress affecting rest and motivation
> • Routine disruptions
> 
> Has anything changed in their daily routine recently?"

**Why it's better**:
- 4 short sentences
- Clean formatting with bullets
- One emoji for context
- Ends with engagement
- Easy to scan and respond to

---

## Formatting Examples

### Sleep Pattern Question

**Good response**:
```
😴 **Gulmira's sleep** dropped from 7.7 to 6.4 hours over the last 9 days - about 76 fewer minutes per night.

When sleep dips like this for several days, it can start affecting energy, mood, and focus. The body needs consistent sleep to recover properly.

Want some ideas on helping them get back on track?
```

**Why it works**:
- 3 short paragraphs
- 1 emoji (sleep context)
- 1-2 bold terms (key metric)
- Ends with actionable question
- Scannable and conversational

### Activity Pattern Question

**Good response**:
```
🚶 Their **step count** dropped 62.8% over 9 days - from about 7,025 to 4,294 steps daily.

This level of decrease typically signals:
• Physical limitation or injury
• Illness or recovery period
• Major routine change

Has anything specific changed in their schedule or energy levels?
```

**Why it works**:
- 2 paragraphs + bullets
- 1 emoji (activity context)
- Bullets for clarity (3 items)
- Direct follow-up question
- Under 6 sentences total

---

## Bad Examples to Avoid

### ❌ Too Long
> "Well, that's an interesting question and I'm glad you asked because there's actually quite a lot to unpack here when we look at Gulmira's data over the past 9 days and what we're seeing is really a sustained pattern of decline across multiple metrics which is important to note because when we see multiple metrics declining simultaneously it often indicates a more systemic issue rather than just an isolated problem with one particular aspect of their health..."

**Problem**: Run-on sentence, no breaks, reads like a monologue

### ❌ Emoji Overload
> "😴 Hey! 👋 So Gulmira's 💤 sleep 🌙 has 📉 dropped 🔻 from ⏰ 7.7 hours 🕐 to 6.4 hours 🕑 over 📅 the last 🗓️ 9 days 📆"

**Problem**: Emoji spam, unreadable, looks unprofessional

### ❌ No Formatting
> "Based on the last 9 days Gulmira's sleep dropped from 7.7 to 6.4 hours and their steps dropped from 7025 to 4294 and this could be caused by physical recovery or illness or increased stress or routine disruptions or mental health factors and I recommend monitoring symptoms and having a conversation and considering medical consultation."

**Problem**: No structure, hard to read, no visual breaks

### ❌ Over-Formatted
> "**Based** on the **last 9 days**, **Gulmira's sleep** **dropped** from **7.7** to **6.4 hours** - that's **76 fewer minutes** per **night**."

**Problem**: Too much bold, distracting, loses emphasis

---

## Summary of All Guardrails

| Guardrail | Rule |
|-----------|------|
| **Length** | 2-3 paragraphs max, 5-6 sentences |
| **Bullets** | Use when listing 2+ items, max 3-4 items |
| **Bold** | 1-2 key terms per response |
| **Emojis** | 1-2 per response, placed naturally |
| **Paragraphs** | Break every 2-3 sentences |
| **Tone** | Expert but warm, never clinical |
| **Addressing** | Always third person about member |
| **Follow-ups** | One question or suggestion to end |

---

## Testing Checklist

Try these messages and verify responses follow guardrails:

- [ ] "What's the pattern?"
  - ✅ Should be 2-3 short paragraphs
  - ✅ Uses 1-2 emojis
  - ✅ Has bold for key metrics
  - ✅ Ends with follow-up question

- [ ] "Why is this happening?"
  - ✅ Uses bullets for causes (3-4 max)
  - ✅ No wall of text
  - ✅ Clean formatting

- [ ] "Tell me more about sleep"
  - ✅ Focused answer, not essay
  - ✅ Uses data from evidence
  - ✅ Asks contextual follow-up

- [ ] "What should I do?"
  - ✅ Actionable suggestions
  - ✅ Bullet list (3-4 items)
  - ✅ Warm but authoritative tone

---

## Final Status

✅ **All deployments complete**  
✅ **Guardrails enforced in prompt**  
✅ **Formatting rules clear**  
✅ **Length limits strict**  
✅ **Emoji usage balanced**  
✅ **Ready for production**

The chat will now provide concise, well-formatted, conversational responses that respect the user's time and attention.
