# Chat Prompt Fix v2 - Caregiver vs Member Distinction

## Problem

The AI was confusing roles:
- **User**: Family caregiver (YOU) viewing a notification
- **Member**: Person whose health data is being shown (Gulmira)

**Example of bug**:
> "Hey Gulmira! So, what's clear from your data is that your average sleep..."

This addressed Gulmira directly, but the USER is the caregiver asking about Gulmira, not Gulmira herself.

## Solution

### 1. Clarified Roles in System Prompt

**Added critical context**:
```typescript
"CRITICAL CONTEXT:",
"- The USER is a family caregiver/parent asking questions",
"- The MEMBER is the person whose health data you're analyzing",
"- Speak TO the caregiver ABOUT the member (third person: 'their', 'they', member's name)",
"- NEVER address the member directly or confuse the caregiver with the member"
```

### 2. Updated Tone (Expert but Warm)

**Before**: Too casual ("Hey! That's a great question...")
**After**: Warm but authoritative ("Based on the last 9 days, [Member]'s average sleep...")

**Key changes**:
- "Warm but authoritative - you're a health expert they can trust"
- "Professional yet approachable, not overly casual"
- "Avoid medical jargon, but don't dumb it down - educate"

### 3. Enhanced Context Message

**Before**:
```
MEMBER: Gulmira
Remember: Use Gulmira's first name naturally. Be conversational.
```

**After**:
```
You are speaking to a FAMILY CAREGIVER about their family member's health data.

FAMILY MEMBER: Gulmira

IMPORTANT: 
- Refer to Gulmira in third person (their, they, Gulmira's)
- You are advising the CAREGIVER, not speaking to Gulmira directly
- Use Gulmira's name when discussing their data
- Be warm but authoritative - a trusted health expert
```

## Expected Response Style

### ✅ Correct (speaks TO caregiver ABOUT member)

> "Based on the last 9 days, **Gulmira's** average sleep dropped from 7.7 to 6.4 hours - that's about 76 fewer minutes per night. When sleep dips like this for several days, it can start to affect energy, mood, and overall wellness.
> 
> Also interesting is **their** step count, which took a big dive—down 62.8%—meaning **they're** moving a lot less than usual. Sometimes less movement can mess with sleep quality or be a sign that **their** body's under some stress or just resting more.
> 
> How have things been going lately with **their** routine or stress levels? Want some ideas on getting back **their** best sleep rhythms?"

### ❌ Wrong (addresses member directly)

> "Hey Gulmira! So, what's clear from **your** data is that **your** average sleep..."

## Tone Comparison

| Aspect | Before | After |
|--------|--------|-------|
| **Authority** | Too casual | Expert but approachable |
| **Addressing** | Direct to member | To caregiver about member |
| **Language** | "Hey! That's a great question..." | "Based on the last 9 days..." |
| **Confidence** | Friendly peer | Trusted advisor |
| **Education** | Simplifies | Educates without jargon |

## Examples

### Question: "What's the pattern?"

**Old response** (wrong):
> "Hey Gulmira! So, what's clear from your data..."

**New response** (correct):
> "Based on the last 9 days, Gulmira's average sleep dropped from 7.7 to 6.4 hours - that's about 76 fewer minutes per night..."

### Question: "Why is this happening?"

**New response** (correct):
> "There are a few common reasons Gulmira's sleep and activity might both be down:
> 
> - Physical recovery from illness or injury
> - Increased stress affecting both rest and motivation
> - Schedule disruptions or routine changes
> - Seasonal factors (weather, schedule shifts)
> 
> Has anything changed in their daily routine recently?"

## Testing

To verify the fix works, try these questions:
1. "What's the pattern?"
2. "Tell me more"
3. "What should I do?"
4. "Why is Gulmira's sleep low?"

**Expected behavior**:
- ✅ Always refers to member in third person (their, they, [name]'s)
- ✅ Speaks TO the caregiver, never addresses member
- ✅ Expert tone - confident, knowledgeable, but warm
- ✅ Uses specific data points from evidence
- ✅ Asks contextual follow-ups to help caregiver understand

## Deployment

Function: `miya_insight_chat` (version 12)
Status: Deployed and ready

## Summary

**Fixed**: AI no longer confuses caregiver with member - always speaks TO you ABOUT them in third person  
**Improved**: More expert/authoritative tone while staying warm and supportive  
**Result**: Feels like consulting a knowledgeable health coach who understands family dynamics
