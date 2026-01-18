"""
Relay it! API - Flask app for Vercel
Screenshot analysis with Gemini Flash
"""

import json
import os
import base64
import logging
from flask import Flask, request, jsonify
from flask_cors import CORS
import google.generativeai as genai

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app, origins=["*"], methods=["GET", "POST", "OPTIONS"], allow_headers=["Content-Type"])

# Configure Gemini
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)


# ============================================================================
# PROMPTS
# ============================================================================

ANALYZE_PROMPT = """Analyze this screenshot and extract structured information.

## Task
1. Perform OCR to extract all visible text from the image
2. Identify the main entity types visible (hotel, restaurant, job posting, product, article, etc.)
3. Write a 1-3 sentence summary of what the screenshot shows. Use objective language (e.g., "A screenshot of...", "A photo showing..."). Do NOT use phrases like "The user is looking at" or "The image displays".
4. Extract structured entities with their attributes
5. Suggest an appropriate category and notebook title

## Categories
- trip-planning: Hotels, flights, restaurants, travel
- shopping: Products, electronics, clothing
- job-search: Job postings, careers
- research: Articles, documentation
- content-writing: Writing, notes, drafts
- productivity: Tasks, calendars, projects
- other: Generic or unclear content

## Output Format
Return a valid JSON object:
{{
  "rawText": "Full OCR text extracted from screenshot",
  "summary": "1-3 sentence objective description (e.g., 'A screenshot of...'). Do NOT say 'The user is looking at...'.",
  "category": "trip-planning|shopping|job-search|research|content-writing|productivity|other",
  "entities": [
    {{
      "type": "hotel|product|job|flight|restaurant|article|other",
      "title": "Entity name/title",
      "attributes": {{}}
    }}
  ],
  "suggestedNotebookTitle": "Short descriptive title for this content"
}}

## Rules
- Extract as much structured information as possible
- For prices, include currency symbol
- For ratings, normalize to a consistent format (e.g., "4.8")
- Return ONLY valid JSON, no markdown code blocks
"""

REGENERATE_PROMPT = """You are an AI assistant for a screenshot capture app. The user has captured screenshots and is now asking a question or wants context about their session.

## Session Context
Category: {session_category}
Previous Summary: {session_summary}

## Captured Screenshots
{screens_data}

## Task
Based on the captured screenshots and their extracted data, respond to the user's context or question embedded in the session summary.

## Output Format
Return a valid JSON object:
{{
  "sessionId": "{session_id}",
  "sessionSummary": "AI response or updated summary based on the screenshots and user's question",
  "sessionCategory": "{session_category}",
  "entities": [],
  "suggestedNotebookTitle": "Suggested title for this session"
}}

## Rules
- Merge duplicate entities from different screenshots
- Provide helpful, conversational responses
- Return ONLY valid JSON, no markdown code blocks
"""

SUMMARIZE_PROMPT = """Generate a comprehensive summary of this research/capture session.

## Session Name
{session_name}

## Entities to Summarize
{entities_data}

## Task
Create a condensed but comprehensive summary with:
1. A 2-4 sentence overview
2. Top 3-5 key highlights
3. 2-3 actionable recommendations
4. Suggested follow-up queries
5. Key topics/tags

## Output Format
Return a valid JSON object:
{{
  "condensedSummary": "2-4 sentence AI-generated overview",
  "keyHighlights": ["Highlight 1", "Highlight 2", "Highlight 3"],
  "recommendations": ["Recommendation 1", "Recommendation 2"],
  "mergedEntities": [],
  "suggestedTitle": "Concise title for this session",
  "suggestedQueries": ["Follow-up question 1?", "Follow-up question 2?"],
  "keywords": ["keyword1", "keyword2", "keyword3"]
}}

## Rules
- Be concise but informative
- Make recommendations actionable
- Return ONLY valid JSON, no markdown code blocks
"""


# ============================================================================
# UTILITIES
# ============================================================================

def get_model():
    """Get configured Gemini model"""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured")
    return genai.GenerativeModel("gemini-2.0-flash")


def parse_json_response(response_text):
    """Parse JSON from Gemini response, handling markdown code blocks"""
    text = response_text.strip()
    
    # Remove markdown code blocks if present
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:-1])
    
    return json.loads(text)


def decode_base64_image(image_data):
    """Decode base64 image, handling data URL prefix"""
    if image_data.startswith("data:"):
        image_data = image_data.split(",")[1]
    return base64.b64decode(image_data)


# ============================================================================
# API ENDPOINTS
# ============================================================================

@app.route("/", methods=["GET"])
@app.route("/api/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "ok",
        "gemini_configured": bool(GEMINI_API_KEY)
    })


@app.route("/api/analyze", methods=["POST"])
def analyze():
    """
    Analyze a screenshot with OCR and entity extraction
    
    Request: {"image": "data:image/png;base64,..."}
    Response: {"rawText": "...", "summary": "...", "category": "...", "entities": [...], "suggestedNotebookTitle": "..."}
    """
    try:
        data = request.get_json()
        if not data or "image" not in data:
            return jsonify({"error": "Missing 'image' field"}), 400

        # Decode image
        image_bytes = decode_base64_image(data["image"])
        image_part = {"mime_type": "image/png", "data": image_bytes}

        # Call Gemini
        model = get_model()
        response = model.generate_content([ANALYZE_PROMPT, image_part])

        # Parse response
        result = parse_json_response(response.text)
        return jsonify(result)

    except Exception as e:
        logger.exception(f"Error in /api/analyze: {e}")
        return jsonify({
            "rawText": "",
            "summary": "",
            "category": "other",
            "entities": [],
            "suggestedNotebookTitle": None
        })


@app.route("/api/regenerate", methods=["POST"])
def regenerate():
    """
    Chat/Q&A about session content
    
    Request: {"sessionId": "...", "previousSession": {...}, "screens": [...]}
    Response: {"sessionId": "...", "sessionSummary": "...", "sessionCategory": "...", "entities": [...], "suggestedNotebookTitle": "..."}
    """
    try:
        data = request.get_json()
        if not data or "sessionId" not in data:
            return jsonify({"error": "Missing 'sessionId' field"}), 400
        if "screens" not in data:
            return jsonify({"error": "Missing 'screens' field"}), 400

        session_id = data["sessionId"]
        screens = data.get("screens", [])
        previous_session = data.get("previousSession", {})

        screens_data = json.dumps(screens, indent=2)
        session_summary = previous_session.get("sessionSummary", "No previous context")
        session_category = previous_session.get("sessionCategory", "other")

        # Build prompt
        prompt = REGENERATE_PROMPT.format(
            session_id=session_id,
            session_category=session_category,
            session_summary=session_summary,
            screens_data=screens_data
        )

        # Call Gemini
        model = get_model()
        response = model.generate_content(prompt)

        # Parse response
        result = parse_json_response(response.text)
        return jsonify(result)

    except Exception as e:
        logger.exception(f"Error in /api/regenerate: {e}")
        return jsonify({
            "sessionId": data.get("sessionId", "") if data else "",
            "sessionSummary": "",
            "sessionCategory": "other",
            "entities": [],
            "suggestedNotebookTitle": None
        })


@app.route("/api/summarize", methods=["POST"])
def summarize():
    """
    Generate AI summary with highlights and recommendations
    
    Request: {"sessionId": "...", "sessionName": "...", "entities": [...]}
    Response: {"condensedSummary": "...", "keyHighlights": [...], "recommendations": [...], ...}
    """
    try:
        data = request.get_json()
        if not data or "sessionId" not in data:
            return jsonify({"error": "Missing 'sessionId' field"}), 400
        if "sessionName" not in data:
            return jsonify({"error": "Missing 'sessionName' field"}), 400
        if "entities" not in data:
            return jsonify({"error": "Missing 'entities' field"}), 400

        session_name = data["sessionName"]
        entities = data["entities"]
        entities_data = json.dumps(entities, indent=2)

        # Build prompt
        prompt = SUMMARIZE_PROMPT.format(
            session_name=session_name,
            entities_data=entities_data
        )

        # Call Gemini
        model = get_model()
        response = model.generate_content(prompt)

        # Parse response
        result = parse_json_response(response.text)
        return jsonify(result)

    except Exception as e:
        logger.exception(f"Error in /api/summarize: {e}")
        return jsonify({
            "condensedSummary": "",
            "keyHighlights": [],
            "recommendations": [],
            "mergedEntities": [],
            "suggestedTitle": "",
            "suggestedQueries": [],
            "keywords": []
        })


# For local development
if __name__ == "__main__":
    app.run(debug=True, port=3000)
