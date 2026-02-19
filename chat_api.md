# Chat API v2

## Endpoint

```
POST /api/chat
```

## What changed from v1

| Change | v1 | v2 |
|--------|----|----|
| Conversation history | Not sent (stateless) | Last 20 messages sent for multi-turn context |
| Entities | Not included | Structured entities included in context |
| Response intent | None | `intent` field classifies AI action |
| Note updates | Full note replacement (`updatedNote`) | Structured `noteOperation` with append/replace |
| Referenced screenshots | Not returned | `referencedScreenshots` IDs returned |
| Follow-up suggestions | None | `suggestedFollowUps` array returned |

---

## Request

### ChatRequest

```json
{
  "sessionId": "string (UUID)",
  "userMessage": "string",
  "conversationHistory": [
    { "role": "user", "content": "string" },
    { "role": "assistant", "content": "string" }
  ],
  "currentNote": "string",
  "context": {
    "screenshots": [
      {
        "id": "string (UUID)",
        "rawText": "string",
        "summary": "string"
      }
    ],
    "entities": [
      {
        "type": "string",
        "title": "string | null",
        "attributes": { "key": "value" }
      }
    ],
    "sessionName": "string | null",
    "sessionCategory": "string | null"
  }
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sessionId` | string | Yes | Session UUID |
| `userMessage` | string | Yes | Current user message |
| `conversationHistory` | array | No | Previous messages (last 20 turns) for multi-turn context |
| `currentNote` | string | Yes | Full markdown content of the user's note |
| `context` | object | No | Session context (screenshots, entities, metadata) |

### conversationHistory

Array of previous messages ordered chronologically. Include the last 20 messages (10 user + 10 assistant turns). This enables the AI to understand references like "tell me more about that" or "compare the first two".

| Field | Type | Description |
|-------|------|-------------|
| `role` | string | `"user"` or `"assistant"` |
| `content` | string | Message text |

### context.screenshots

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Screenshot UUID |
| `rawText` | string | OCR-extracted text from the screenshot |
| `summary` | string | AI-generated summary of the screenshot |

### context.entities

Structured data extracted from screenshots. Providing this lets the AI reason about structured attributes (prices, ratings, dates) rather than only raw text.

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Entity type (e.g. `"product"`, `"hotel"`, `"job-listing"`) |
| `title` | string or null | Entity display name |
| `attributes` | object | Key-value pairs of extracted data |

### context metadata

| Field | Type | Description |
|-------|------|-------------|
| `sessionName` | string or null | Current session name |
| `sessionCategory` | string or null | Session category (e.g. `"shopping"`, `"research"`) |

---

## Response

### ChatResponse

```json
{
  "reply": "string",
  "intent": "answer | modify_note | summarize | compare | recommend",
  "noteOperation": {
    "type": "append | replace | no_change",
    "content": "string | null",
    "section": "string | null"
  },
  "referencedScreenshots": ["uuid1", "uuid2"],
  "suggestedFollowUps": ["Compare prices", "Add this to my note"]
}
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `reply` | string | AI response text displayed in chat |
| `intent` | string or null | What the AI did -- used by client for rendering |
| `noteOperation` | object or null | Structured note modification (replaces v1 `noteWasModified` + `updatedNote`) |
| `referencedScreenshots` | array or null | Screenshot UUIDs the AI referenced in its answer |
| `suggestedFollowUps` | array or null | Quick-reply suggestions for the user |

### intent values

| Value | Meaning | Client behavior |
|-------|---------|-----------------|
| `answer` | Answered a question | Standard chat bubble |
| `modify_note` | Modified the user's note | Show note-update inline block |
| `summarize` | Generated a summary | Show summary card in chat |
| `compare` | Compared items | Highlight referenced screenshots |
| `recommend` | Made a recommendation | Show as recommendation card |

### noteOperation

Replaces the v1 pattern of sending back the entire note. More efficient and enables partial updates.

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"append"` (add to end), `"replace"` (replace entire note), `"no_change"` |
| `content` | string or null | The new/changed markdown content (null when `type` is `"no_change"`) |
| `section` | string or null | Optional section heading to target (e.g. `"## Summary"`) |

**Client-side logic:**
- `append`: Append `content` to the current note (with `\n\n` separator)
- `replace`: Replace the entire note with `content`
- `no_change`: Do nothing to the note

---

## Examples

### 1. Simple question (multi-turn)

**Request:**

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "userMessage": "Which one has the best rating?",
  "conversationHistory": [
    { "role": "user", "content": "Show me a comparison of these products" },
    { "role": "assistant", "content": "Here are the 3 products from your screenshots:\n1. iPhone 16 - $999, 4.5 stars\n2. Pixel 9 - $899, 4.3 stars\n3. Galaxy S25 - $949, 4.4 stars" }
  ],
  "currentNote": "",
  "context": {
    "screenshots": [
      {
        "id": "aaa-111",
        "rawText": "iPhone 16 Pro...",
        "summary": "Apple iPhone 16 product page"
      }
    ],
    "entities": [
      {
        "type": "product",
        "title": "iPhone 16",
        "attributes": { "price": "$999", "rating": "4.5" }
      },
      {
        "type": "product",
        "title": "Pixel 9",
        "attributes": { "price": "$899", "rating": "4.3" }
      }
    ],
    "sessionName": "Phone Research",
    "sessionCategory": "shopping"
  }
}
```

**Response:**

```json
{
  "reply": "The iPhone 16 has the best rating at 4.5 stars, though it's also the most expensive at $999. The Galaxy S25 is a close second at 4.4 stars for $949.",
  "intent": "compare",
  "noteOperation": {
    "type": "no_change",
    "content": null,
    "section": null
  },
  "referencedScreenshots": ["aaa-111"],
  "suggestedFollowUps": [
    "Add this comparison to my note",
    "Which has the best value for money?",
    "Summarize all products"
  ]
}
```

### 2. Note modification

**Request:**

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "userMessage": "Add a summary of my research to the note",
  "conversationHistory": [],
  "currentNote": "# Phone Research\n\nLooking at new phones.",
  "context": {
    "entities": [
      {
        "type": "product",
        "title": "iPhone 16",
        "attributes": { "price": "$999", "rating": "4.5" }
      }
    ],
    "sessionName": "Phone Research",
    "sessionCategory": "shopping"
  }
}
```

**Response:**

```json
{
  "reply": "I've added a research summary to your note with key findings and a comparison table.",
  "intent": "modify_note",
  "noteOperation": {
    "type": "append",
    "content": "## Research Summary\n\n| Phone | Price | Rating |\n|-------|-------|--------|\n| iPhone 16 | $999 | 4.5 |\n\n**Key Finding:** The iPhone 16 leads in ratings but is the most expensive option.",
    "section": null
  },
  "referencedScreenshots": [],
  "suggestedFollowUps": [
    "What else should I consider?",
    "Compare with budget options"
  ]
}
```

### 3. First message (no history)

**Request:**

```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "userMessage": "What have I captured so far?",
  "conversationHistory": [],
  "currentNote": "",
  "context": {
    "screenshots": [
      {
        "id": "aaa-111",
        "rawText": "Marriott Downtown - $199/night...",
        "summary": "Hotel booking page for Marriott"
      },
      {
        "id": "bbb-222",
        "rawText": "Hilton Garden Inn - $159/night...",
        "summary": "Hotel booking page for Hilton"
      }
    ],
    "entities": [
      {
        "type": "hotel",
        "title": "Marriott Downtown",
        "attributes": { "price": "$199/night", "rating": "4.5" }
      },
      {
        "type": "hotel",
        "title": "Hilton Garden Inn",
        "attributes": { "price": "$159/night", "rating": "4.2" }
      }
    ],
    "sessionName": "Trip Planning",
    "sessionCategory": "trip-planning"
  }
}
```

**Response:**

```json
{
  "reply": "You've captured 2 hotel options:\n\n1. **Marriott Downtown** - $199/night (4.5 stars)\n2. **Hilton Garden Inn** - $159/night (4.2 stars)\n\nThe Marriott is pricier but higher rated. The Hilton is $40/night cheaper.",
  "intent": "summarize",
  "noteOperation": {
    "type": "no_change",
    "content": null,
    "section": null
  },
  "referencedScreenshots": ["aaa-111", "bbb-222"],
  "suggestedFollowUps": [
    "Which hotel has the best value?",
    "Add this comparison to my note",
    "What should I look for in a hotel?"
  ]
}
```

---

## Backend Implementation Notes

### System prompt guidance

The backend should instruct the AI to:
1. Always classify its `intent` based on what the user asked
2. Only set `noteOperation.type` to `"append"` or `"replace"` when the user explicitly asks to modify the note
3. Return `referencedScreenshots` as the IDs of screenshots it drew information from
4. Generate 2-3 `suggestedFollowUps` that are contextually relevant
5. Use `conversationHistory` to maintain coherent multi-turn dialogue
6. Use `entities` for structured reasoning (comparisons, rankings) rather than parsing raw OCR text

### Token budget

To manage token limits:
- `conversationHistory`: Cap at 20 messages. If more exist, send the most recent 20.
- `context.screenshots`: Send all, but truncate `rawText` to 2000 chars each if needed.
- `context.entities`: Send all entities (they're compact).
- `currentNote`: Send full note (usually small).

### Backward compatibility

The backend should accept both v1 and v2 requests:
- If `conversationHistory` is missing, treat as empty (stateless).
- If response fields `intent`, `noteOperation`, `suggestedFollowUps` are missing, the client falls back to v1 behavior (`noteWasModified` + `updatedNote`).

---

## Error Handling

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 400 | Bad request (malformed JSON, missing required fields) |
| 429 | Rate limited |
| 500 | Server error (AI provider failure, etc.) |

---

## Swift Types

```swift
struct ChatHistoryMessage: Codable {
    let role: String
    let content: String
}

struct ChatEntity: Encodable {
    let type: String
    let title: String?
    let attributes: [String: String]
}

struct ChatContext: Encodable {
    let screenshots: [ChatScreenshot]?
    let entities: [ChatEntity]?
    let sessionName: String?
    let sessionCategory: String?
}

struct ChatScreenshot: Encodable {
    let id: String
    let rawText: String
    let summary: String
}

struct ChatRequest: Encodable {
    let sessionId: String
    let userMessage: String
    let conversationHistory: [ChatHistoryMessage]?
    let currentNote: String
    let context: ChatContext?
}

struct NoteOperation: Decodable {
    let type: String      // "append", "replace", "no_change"
    let content: String?
    let section: String?
}

struct ChatResponse: Decodable {
    let reply: String
    let intent: String?
    let noteOperation: NoteOperation?
    let referencedScreenshots: [String]?
    let suggestedFollowUps: [String]?
    // v1 backward compat
    let updatedNote: String?
    let noteWasModified: Bool?
}
```
