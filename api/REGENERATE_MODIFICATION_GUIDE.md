# Regenerate Endpoint Modification Guide

## Current Format (Your API)

Your current `/api/regenerate` endpoint receives:

```typescript
interface RegenerateRequest {
  sessionId: string;
  previousSession?: {
    sessionSummary: string;
    sessionCategory: string;
    entities: Entity[];
  };
  screens: {
    id: string;
    analysis: AnalyzeResponse;
  }[];
}
```

## Proposed Change: Add `userQuery` Field

To support the chat feature, add a `userQuery` field to the request:

```typescript
interface RegenerateRequest {
  sessionId: string;
  previousSession?: {
    sessionSummary: string;
    sessionCategory: string;
    entities: Entity[];
  };
  screens: {
    id: string;
    analysis: AnalyzeResponse;
  }[];
  userQuery?: string;  // NEW: User's question or instruction
}
```

## How to Modify Your Prompt

In your `regenerate_route.ts`, update the prompt to handle the user query:

```typescript
// Add this after building the basic prompt
if (reqBody.userQuery) {
  prompt += `
--- USER QUERY ---
The user is asking: "${reqBody.userQuery}"

Please address their question in your response. The sessionSummary should directly answer their question based on the collected data.

For example:
- If they ask "Which hotel is cheapest?", analyze prices and recommend the cheapest option.
- If they ask "Summarize my job search", provide an overview of the jobs they've looked at.
- If they ask "Compare these products", create a comparison based on attributes.

`;
}
```

## Response Format (No Change Needed)

Your current response format already works:

```typescript
interface RegenerateResponse {
  sessionId: string;
  sessionSummary: string;  // This will now answer the user's question
  sessionCategory: string;
  entities: Entity[];
  suggestedNotebookTitle: string | null;
  suggestions: Suggestion[];
}
```

## Full Example

### Request with User Query
```json
{
  "sessionId": "abc-123",
  "userQuery": "Which hotel offers the best value for money?",
  "previousSession": {
    "sessionSummary": "User is researching hotels in Tokyo",
    "sessionCategory": "trip-planning",
    "entities": [...]
  },
  "screens": [...]
}
```

### Expected Response
```json
{
  "sessionId": "abc-123",
  "sessionSummary": "Based on your research, the Park Hyatt Tokyo offers the best value at $350/night with a 9.2 rating. It has better amenities than the cheaper Shinjuku Washington ($200/night, 7.8 rating) while being significantly less expensive than the Aman Tokyo ($1200/night).",
  "sessionCategory": "trip-planning",
  "entities": [...],
  "suggestedNotebookTitle": "Tokyo Hotels Comparison",
  "suggestions": [
    {
      "type": "next-step",
      "text": "Consider checking availability for your travel dates"
    }
  ]
}
```

## Swift Side Update Needed

Once you add `userQuery` support, I'll update the Swift code to send the user's chat message in that field instead of appending it to `previousSession.sessionSummary`.

---

## Quick Implementation Checklist

1. [ ] Add `userQuery?: string` to `RegenerateRequest` interface
2. [ ] Update prompt to check for `userQuery` and instruct AI to answer it
3. [ ] Test with a sample query
4. [ ] Let me know when done so I can update the Swift code
