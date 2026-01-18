# Summarize Endpoint Guide

## New Endpoint: POST /api/summarize

This endpoint takes all entities from a session and uses AI to create a condensed, intelligent summary.

## Request Format

```typescript
interface SummarizeRequest {
  sessionId: string;
  sessionName: string;
  entities: {
    type: string;
    title: string | null;
    attributes: Record<string, string>;
  }[];
}
```

## Response Format

```typescript
interface SummarizeResponse {
  condensedSummary: string;      // AI-generated overview (2-4 sentences)
  keyHighlights: string[];       // Top 3-5 bullet points
  recommendations: string[];     // AI suggestions based on content
  mergedEntities: {              // Deduplicated/merged entities
    type: string;
    title: string | null;
    attributes: Record<string, string>;
  }[];
  suggestedTitle: string;        // AI-suggested session title
}
```

## Example Request

```json
{
  "sessionId": "abc-123",
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
    },
    {
      "type": "hotel", 
      "title": "W Taipei",
      "attributes": {
        "price": "$300/night",
        "rating": "4.6",
        "location": "Xinyi District"
      }
    },
    {
      "type": "restaurant",
      "title": "Din Tai Fung",
      "attributes": {
        "cuisine": "Taiwanese",
        "rating": "4.9"
      }
    }
  ]
}
```

## Example Response

```json
{
  "condensedSummary": "Planning a trip to Taipei with focus on luxury hotels in Xinyi District. The Grand Hyatt offers better value at $250/night with a higher rating than W Taipei. Din Tai Fung is a must-visit for authentic Taiwanese cuisine.",
  "keyHighlights": [
    "Grand Hyatt Taipei: Best value at $250/night, 4.8 rating",
    "W Taipei: Premium option at $300/night",
    "Din Tai Fung: Top-rated Taiwanese restaurant (4.9)"
  ],
  "recommendations": [
    "Book Grand Hyatt for best price-to-quality ratio",
    "Make Din Tai Fung reservation in advance - very popular",
    "Both hotels are in Xinyi District - convenient for exploring"
  ],
  "mergedEntities": [
    {
      "type": "hotel-comparison",
      "title": "Taipei Hotels Comparison",
      "attributes": {
        "best_value": "Grand Hyatt ($250, 4.8★)",
        "premium_option": "W Taipei ($300, 4.6★)",
        "location": "Xinyi District"
      }
    },
    {
      "type": "restaurant",
      "title": "Din Tai Fung",
      "attributes": {
        "cuisine": "Taiwanese",
        "rating": "4.9",
        "note": "Must-visit"
      }
    }
  ],
  "suggestedTitle": "Taipei Trip: Hotels & Dining"
}
```

## Implementation Prompt (for your API)

```typescript
const SUMMARIZE_PROMPT = `You are a research assistant that creates condensed summaries.

Given a collection of entities the user has gathered, create:
1. A 2-4 sentence overview summarizing the research
2. 3-5 key highlights as bullet points
3. 2-3 actionable recommendations
4. Merged/deduplicated entities (combine similar items)
5. A suggested title for this collection

Session Name: {{sessionName}}

Entities:
{{entities}}

Return JSON:
{
  "condensedSummary": "...",
  "keyHighlights": ["...", "..."],
  "recommendations": ["...", "..."],
  "mergedEntities": [...],
  "suggestedTitle": "..."
}`;
```

## File Location

Create: `/api/summarize_route.ts`

## Swift Integration

Once you create this endpoint, I'll update the Swift code to call it instead of doing manual summarization.
