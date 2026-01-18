# Chat API Endpoint

## `POST /api/chat`

AI-powered chat that can read and modify note content based on user commands.

---

## Request Body

```json
{
  "sessionId": "uuid-string",
  "userMessage": "I don't like the third recommendation, remove it",
  "currentNote": "# Trip Planning\n\n## Summary\n...\n\n## Recommendations\n- First rec\n- Second rec\n- Third rec",
  "context": {
    "screenshots": [
      {
        "id": "screenshot-uuid",
        "rawText": "OCR text from screenshot...",
        "summary": "AI summary of this screenshot"
      }
    ],
    "sessionName": "Japan Trip Planning",
    "sessionCategory": "travel"
  }
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sessionId` | string | Yes | Session UUID |
| `userMessage` | string | Yes | User's chat message/command |
| `currentNote` | string | Yes | Current note content (markdown) |
| `context.screenshots` | array | No | Screenshots for context |
| `context.sessionName` | string | No | Session name |
| `context.sessionCategory` | string | No | Category (travel, shopping, research, etc.) |

---

## Response Body

```json
{
  "reply": "Done! I've removed the third recommendation from your notes.",
  "updatedNote": "# Trip Planning\n\n## Summary\n...\n\n## Recommendations\n- First rec\n- Second rec",
  "noteWasModified": true
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `reply` | string | AI's conversational response to display in chat |
| `updatedNote` | string | The complete modified note content (only if `noteWasModified` is true) |
| `noteWasModified` | boolean | Whether the AI made changes to the note |

---

## Behavior

### Edit Commands (noteWasModified = true)
- "Remove the third recommendation"
- "Rewrite the summary to be shorter"  
- "Add a section about budget"
- "Delete the highlights section"
- "Change the title to 'My Japan Adventure'"

### Question Commands (noteWasModified = false)
- "What hotels did I look at?"
- "Summarize what's in my notes"
- "What was the price of the second hotel?"

---

## Example Requests

### Edit Request
```bash
curl -X POST https://your-api.vercel.app/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "abc-123",
    "userMessage": "Remove the third recommendation",
    "currentNote": "# Notes\n\n## Recommendations\n- One\n- Two\n- Three",
    "context": {}
  }'
```

### Response
```json
{
  "reply": "Done! I removed the third recommendation.",
  "updatedNote": "# Notes\n\n## Recommendations\n- One\n- Two",
  "noteWasModified": true
}
```

### Question Request
```bash
curl -X POST https://your-api.vercel.app/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "abc-123",
    "userMessage": "What recommendations do I have?",
    "currentNote": "# Notes\n\n## Recommendations\n- One\n- Two",
    "context": {}
  }'
```

### Response
```json
{
  "reply": "You have 2 recommendations:\n1. One\n2. Two",
  "noteWasModified": false
}
```

---

## AI Prompt Guidelines

The AI should:
1. **Parse user intent** - Is this an edit command or a question?
2. **If editing**: Return the full modified `updatedNote` with changes applied
3. **If questioning**: Answer based on note content and screenshot context
4. **Keep formatting**: Preserve markdown structure when editing
5. **Be concise**: Short, helpful replies

---

## Error Response

```json
{
  "error": "Invalid request",
  "message": "currentNote is required"
}
```

Status codes:
- `200` - Success
- `400` - Bad request (missing fields)
- `500` - Server error
