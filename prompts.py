"""
Gemini prompts for screenshot analysis
"""

ANALYZE_PROMPT = """You are an AI assistant that analyzes screenshots and extracts structured information.

## Task
1. Perform OCR to extract all visible text from the image
2. Identify the main entity type (e.g., hotel, restaurant, job posting, product, article, etc.)
3. Extract structured information based on the entity type
4. Compare with existing entities to determine if this is the same entity (different page/view)

## Existing Entities in Session
{existing_entities}

## Output Format
Return a valid JSON object with this structure:
{{
  "raw_text": "All extracted text from the image...",
  "entity": {{
    "type": "hotel|restaurant|job|product|article|other",
    "is_new": true|false,
    "merge_with_id": "uuid if merging with existing entity, null otherwise",
    "confidence": 0.0-1.0,
    "data": {{
      // Structured data based on entity type
      // For hotel: name, price, location, amenities[], rating, etc.
      // For job: title, company, salary, location, requirements[], etc.
      // For product: name, price, brand, features[], specs, etc.
      // For restaurant: name, cuisine, price_range, location, rating, etc.
      // Include all relevant fields found in the screenshot
    }}
  }}
}}

## Rules
- Extract as much structured information as possible
- If the screenshot shows the same entity as an existing one (same hotel, job, etc.), set is_new=false and provide merge_with_id
- Use context clues to determine entity type (URL, layout, keywords)
- For prices, include currency symbol
- For ratings, normalize to a consistent format
- Return ONLY valid JSON, no markdown code blocks
"""

REGENERATE_PROMPT = """You are an AI assistant that synthesizes information from multiple screenshots.

## Task
Given the extracted data from multiple screenshots (after some deletions), create a unified summary.

## Remaining Data
{remaining_data}

## Deleted Item IDs (exclude these)
{deleted_ids}

## Output Format
Return a valid JSON array with consolidated entities:
[
  {{
    "entity_type": "hotel|restaurant|job|product|article|other",
    "source_screenshot_ids": ["uuid1", "uuid2"],
    "data": {{
      // Merged and consolidated data from all sources
      // Combine information, prefer more detailed/recent data
      // Remove any contradictory information from deleted sources
    }}
  }}
]

## Rules
- Merge information from multiple screenshots of the same entity
- Remove any data that came exclusively from deleted screenshots
- Consolidate duplicate information
- Keep the most complete and accurate version of each field
- Return ONLY valid JSON, no markdown code blocks
"""
