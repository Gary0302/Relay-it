# Relay it! API Documentation

**Base URL (Production):** `https://relay-that-backend.vercel.app`  
**Base URL (Local):** `http://localhost:3000`

---

## Overview

The Relay it! API provides three main endpoints for analyzing screenshots, managing sessions, and generating AI summaries.

| Endpoint | Purpose |
|----------|---------|
| `POST /api/analyze` | Analyze a single screenshot with OCR and entity extraction |
| `POST /api/regenerate` | Chat/Q&A about session content, update session context |
| `POST /api/summarize` | Generate condensed AI summary with highlights and recommendations |

---

## POST /api/analyze

Analyzes a single screenshot and extracts structured information using OCR and AI.

### Request

```json
{
  "image": "data:image/png;base64,iVBORw0KGg..."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `image` | string | Yes | PNG data URL with base64 encoded image |

### Response

```json
{
  "rawText": "Full OCR text extracted from screenshot",
  "summary": "1-3 sentence description of what the user is viewing",
  "category": "trip-planning",
  "entities": [
    {
      "type": "hotel",
      "title": "Grand Hyatt Taipei",
      "attributes": {
        "price": "$250/night",
        "rating": "4.8",
        "location": "Xinyi District"
      }
    }
  ],
  "suggestedNotebookTitle": "Taipei Hotels"
}
```

### Categories

| Category | Description |
|----------|-------------|
| `trip-planning` | Hotels, flights, restaurants, travel |
| `shopping` | Products, electronics, clothing |
| `job-search` | Job postings, careers |
| `research` | Articles, documentation |
| `content-writing` | Writing, notes, drafts |
| `productivity` | Tasks, calendars, projects |
| `other` | Generic or unclear content |

### Common Entity Types

| Type | Common Attributes |
|------|-------------------|
| `hotel` | price, rating, location, stars, reviews, amenities |
| `product` | price, brand, model, specs, availability |
| `job` | company, salary, location, employment_type |
| `flight` | airline, origin, destination, departure, price |
| `restaurant` | cuisine, rating, price_level, location |
| `article` | author, date, source, topic |

---

## POST /api/regenerate

Handles chat/Q&A about session content. Used for asking questions about captured screenshots and entities.

### Request

```json
{
  "sessionId": "uuid-string",
  "previousSession": {
    "sessionSummary": "Previous context + user question",
    "sessionCategory": "trip-planning",
    "entities": [...]
  },
  "screens": [
    {
      "id": "screenshot-uuid",
      "analysis": {
        "rawText": "OCR text",
        "summary": "Screen summary",
        "category": "trip-planning",
        "entities": [...],
        "suggestedNotebookTitle": null
      }
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sessionId` | string | Yes | Unique session identifier |
| `previousSession` | object | No | Previous session state for context |
| `previousSession.sessionSummary` | string | Yes* | Include user question here |
| `previousSession.sessionCategory` | string | Yes* | Session category |
| `previousSession.entities` | array | Yes* | Previous entities |
| `screens` | array | Yes | Current screenshots with analysis |

### Response

```json
{
  "sessionId": "uuid-string",
  "sessionSummary": "AI response to the user's question",
  "sessionCategory": "trip-planning",
  "entities": [...],
  "suggestedNotebookTitle": "Trip Planning Notes"
}
```

---

## POST /api/summarize

Generates a condensed AI summary with highlights, recommendations, and suggested follow-up queries.

### Request

```json
{
  "sessionId": "uuid-string",
  "sessionName": "Trip to Taiwan",
  "entities": [
    {
      "type": "hotel",
      "title": "Grand Hyatt Taipei",
      "attributes": {
        "price": "$250/night",
        "rating": "4.8",
        "location": "Xinyi District"
      }
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sessionId` | string | Yes | Unique session identifier |
| `sessionName` | string | Yes | Name of the session |
| `entities` | array | Yes | All entities to summarize |

### Response

```json
{
  "condensedSummary": "AI-generated overview (2-4 sentences)",
  "keyHighlights": [
    "Grand Hyatt: Best value at $250/night",
    "W Taipei: Premium option at $300/night",
    "Both hotels in Xinyi District"
  ],
  "recommendations": [
    "Book Grand Hyatt for best price-to-quality",
    "Reserve Din Tai Fung in advance"
  ],
  "mergedEntities": [...],
  "suggestedTitle": "Taipei Trip: Hotels & Dining",
  "suggestedQueries": [
    "Compare prices between the hotels",
    "What are the best restaurants nearby?",
    "Show me flight options to Taipei"
  ],
  "keywords": ["Taipei", "hotels", "travel", "Xinyi District"]
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `condensedSummary` | string | 2-4 sentence AI-generated overview |
| `keyHighlights` | string[] | Top 3-5 bullet point highlights |
| `recommendations` | string[] | 2-3 actionable suggestions |
| `mergedEntities` | array | Deduplicated/merged entities |
| `suggestedTitle` | string | AI-suggested session title |
| `suggestedQueries` | string[] | **NEW**: Follow-up questions to ask |
| `keywords` | string[] | **NEW**: Key topics/tags |

---

## Database Schema

### Tables

#### `sessions`
| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Foreign key to auth.users |
| `name` | TEXT | Session name |
| `description` | TEXT | Optional description |
| `created_at` | TIMESTAMPTZ | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | Last update timestamp |

#### `screenshots`
| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `session_id` | UUID | Foreign key to sessions |
| `image_url` | TEXT | Storage URL |
| `order_index` | INT | Display order |
| `raw_text` | TEXT | OCR text |
| `created_at` | TIMESTAMPTZ | Creation timestamp |

#### `extracted_info`
| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `session_id` | UUID | Foreign key to sessions |
| `screenshot_ids` | UUID[] | Related screenshots |
| `entity_type` | TEXT | Type (hotel, product, ai-summary, etc.) |
| `data` | JSONB | Entity attributes |
| `is_deleted` | BOOLEAN | Soft delete flag |
| `created_at` | TIMESTAMPTZ | Creation timestamp |

#### `chat_messages`
| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `session_id` | UUID | Foreign key to sessions |
| `role` | TEXT | 'user' or 'assistant' |
| `content` | TEXT | Message content |
| `created_at` | TIMESTAMPTZ | Creation timestamp |

---

## Error Handling

All endpoints return valid JSON even on errors:

```json
{
  "rawText": "",
  "summary": "",
  "category": "other",
  "entities": [],
  "suggestedNotebookTitle": null
}
```

---

## CORS

All endpoints allow cross-origin requests:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`
