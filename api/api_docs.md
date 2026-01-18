# API Documentation

## Endpoints

### 1. POST /api/analyze

Analyzes a single screenshot and extracts structured information.

### 2. POST /api/regenerate

Regenerates session-level analysis from multiple screenshot analyses.

---

## POST /api/analyze

Base URL (Production): `https://relay-that-backend-ibaiy8nho-andrewmahran7s-projects.vercel.app`

Base URL (Local): `http://localhost:3000`

## Request

### Headers
```
Content-Type: application/json
```

### Body
```json
{
  "image": "data:image/png;base64,iVBORw0KGg..."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `image` | string | Yes | PNG data URL with base64 encoded image |

## Response

### Success Response (200 OK)

```json
{
  "rawText": "string",
  "summary": "string",
  "category": "string",
  "entities": [
    {
      "type": "string",
      "title": "string | null",
      "attributes": {
        "key": "value"
      }
    }
  ],
  "suggestedNotebookTitle": "string | null"
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `rawText` | string | Full OCR text extracted from screenshot |
| `summary` | string | 1-3 sentence description of screenshot content |
| `category` | string | One of: `trip-planning`, `shopping`, `job-search`, `research`, `content-writing`, `productivity`, `other` |
| `entities` | array | List of extracted items/objects |
| `entities[].type` | string | Entity type (e.g., `hotel`, `product`, `job`, `flight`) |
| `entities[].title` | string\|null | Main name/title of the entity |
| `entities[].attributes` | object | Key-value pairs of entity metadata |
| `suggestedNotebookTitle` | string\|null | Suggested notebook title based on context |

## Example

### Request
```bash
curl -X POST https://relay-that-backend-ibaiy8nho-andrewmahran7s-projects.vercel.app/api/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "image": "data:image/png;base64,iVBORw0KGgoAAAA..."
  }'
```

### Response
```json
{
  "rawText": "One&Only Palmilla, Los Cabos\n5 stars\n9.8 Exceptional\n652 reviews\n$850/night\nBeachfront Resort",
  "summary": "User is viewing a luxury beachfront hotel in Los Cabos with exceptional ratings and premium pricing.",
  "category": "trip-planning",
  "entities": [
    {
      "type": "hotel",
      "title": "One&Only Palmilla",
      "attributes": {
        "location": "Los Cabos, Baja California",
        "price": "$850/night",
        "rating": "9.8 Exceptional",
        "stars": "5",
        "reviews": "652",
        "amenities": "Beachfront, VIP Access"
      }
    }
  ],
  "suggestedNotebookTitle": "Los Cabos Hotels"
}
```

## Categories

| Category | Description | Example Use Cases |
|----------|-------------|-------------------|
| `trip-planning` | Travel research | Hotels, flights, restaurants, rentals |
| `shopping` | Product research | Electronics, clothing, comparisons |
| `job-search` | Career hunting | Job postings, company research |
| `research` | Information gathering | Articles, documentation, courses |
| `content-writing` | Writing & editing | Drafts, notes, writing tools |
| `productivity` | Task management | Tasks, calendars, project management |
| `other` | Everything else | Generic or unclear content |

## Common Entity Types

| Type | Common Attributes |
|------|-------------------|
| `hotel` | price, rating, location, stars, reviews, amenities, url |
| `product` | price, brand, model, specs, color, availability, url |
| `job` | company, salary, location, employment_type, work_mode |
| `flight` | airline, flight_number, origin, destination, departure, arrival, price, class |
| `restaurant` | cuisine, rating, reviews, price_level, location, hours |
| `article` | author, date, source, read_time, topic, url |
| `course` | instructor, institution, platform, duration, level, price |
| `rental` | bedrooms, bathrooms, size, price, rating, reviews, location |

## Error Handling

The API always returns a valid response. On error, returns:

```json
{
  "rawText": "",
  "summary": "",
  "category": "other",
  "entities": [],
  "suggestedNotebookTitle": null
}
```

No error is thrown - the fallback ensures frontend can continue working.

## CORS

Cross-origin requests are allowed:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`

---

## POST /api/regenerate

Regenerates session-level summary and entities from multiple screenshot analyses.

### Purpose

Called when the session/notebook changes (screenshot added/deleted). Does NOT take images - only takes JSON outputs from `/api/analyze` plus previous session state. Returns updated session-level summary, category, and merged entities WITHOUT restarting the idea.

### Request

#### Headers
```
Content-Type: application/json
```

#### Body
```json
{
  "sessionId": "string",
  "previousSession": {
    "sessionSummary": "string",
    "sessionCategory": "string",
    "entities": [...]
  },
  "screens": [
    {
      "id": "string",
      "analysis": {
        "rawText": "string",
        "summary": "string",
        "category": "string",
        "entities": [...],
        "suggestedNotebookTitle": "string | null"
      }
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sessionId` | string | Yes | Unique session/notebook identifier |
| `previousSession` | object | No | Previous session state (maintains continuity) |
| `previousSession.sessionSummary` | string | Yes* | Previous session summary |
| `previousSession.sessionCategory` | string | Yes* | Previous session category |
| `previousSession.entities` | array | Yes* | Previous merged entities |
| `screens` | array | Yes | All CURRENT screenshots with their analysis |
| `screens[].id` | string | Yes | Screenshot identifier |
| `screens[].analysis` | object | Yes | Full AnalyzeResponse from /api/analyze |

*Required if `previousSession` is provided

### Response

#### Success Response (200 OK)

```json
{
  "sessionId": "string",
  "sessionSummary": "string",
  "sessionCategory": "string",
  "entities": [...],
  "suggestedNotebookTitle": "string | null"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sessionId` | string | Same session ID from request |
| `sessionSummary` | string | 1-3 sentence description of entire session |
| `sessionCategory` | string | Overall category for the session |
| `entities` | array | Merged/deduplicated entities across all screens |
| `suggestedNotebookTitle` | string\|null | Suggested notebook title |

### Example

#### Request
```bash
curl -X POST http://localhost:3000/api/regenerate \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "session-123",
    "previousSession": {
      "sessionSummary": "User is researching hotels in Los Cabos",
      "sessionCategory": "trip-planning",
      "entities": [...]
    },
    "screens": [
      {
        "id": "screen-1",
        "analysis": {
          "rawText": "One&Only Palmilla...",
          "summary": "Luxury hotel in Los Cabos",
          "category": "trip-planning",
          "entities": [...],
          "suggestedNotebookTitle": "Los Cabos Hotels"
        }
      }
    ]
  }'
```

#### Response
```json
{
  "sessionId": "session-123",
  "sessionSummary": "User is planning a luxury trip to Los Cabos, comparing high-end resorts and flight options.",
  "sessionCategory": "trip-planning",
  "entities": [
    {
      "type": "hotel",
      "title": "One&Only Palmilla",
      "attributes": {
        "location": "Los Cabos, Mexico",
        "price": "$850/night",
        "rating": "9.8 Exceptional"
      }
    },
    {
      "type": "flight",
      "title": "UA 1234 SFO → SJD",
      "attributes": {
        "airline": "United Airlines",
        "price": "$450",
        "class": "Economy"
      }
    }
  ],
  "suggestedNotebookTitle": "Los Cabos Trip Planning"
}
```

### Behavior Notes

1. **Maintains Continuity**: Uses `previousSession` to avoid restarting or drifting from the core idea
2. **Merges Entities**: Intelligently deduplicates similar entities across screens
3. **Updates Summary**: Refines session-level summary based on all current screens
4. **Never Restarts**: The AI is instructed to maintain the established context
5. **Fallback on Error**: Always returns valid JSON, even if Gemini API fails

### Test Script

Run locally:
```bash
node test-regenerate.mjs
```

### CORS

Cross-origin requests are allowed (same as /api/analyze)