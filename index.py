"""
Relay it! - Flask API for Vercel
Screenshot analysis with Gemini Flash
"""

import json
import os
import base64
import logging
from typing import List, Dict, Any, Optional
from flask import Flask, request, jsonify
from flask_cors import CORS
from pydantic import BaseModel, field_validator, ValidationError
import google.generativeai as genai
from dotenv import load_dotenv

from prompts import ANALYZE_PROMPT, REGENERATE_PROMPT

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app, origins=["*"])

# Configure Gemini
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)


# Pydantic models for request validation
class ExistingEntity(BaseModel):
    id: str
    type: str
    data: Dict[str, Any]


class AnalyzeRequest(BaseModel):
    image: str  # base64 encoded image
    session_id: str
    existing_entities: List[ExistingEntity] = []

    @field_validator("image")
    @classmethod
    def validate_image(cls, v: str) -> str:
        # Remove data URL prefix if present
        if v.startswith("data:"):
            v = v.split(",")[1]
        # Validate base64
        try:
            base64.b64decode(v)
        except Exception:
            raise ValueError("Invalid base64 image data")
        return v


class ScreenshotData(BaseModel):
    id: str
    raw_text: str
    data: Dict[str, Any]


class RegenerateRequest(BaseModel):
    session_id: str
    deleted_ids: List[str]
    remaining_screenshots: List[ScreenshotData]


def analyze_with_gemini(image_base64: str, existing_entities: List[Dict]) -> Dict[str, Any]:
    """Analyze screenshot with Gemini Flash"""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured")

    # Format existing entities for prompt
    entities_str = json.dumps(existing_entities, indent=2) if existing_entities else "None"
    
    # Create the prompt
    prompt = ANALYZE_PROMPT.format(existing_entities=entities_str)
    
    # Configure Gemini model
    model = genai.GenerativeModel("gemini-2.0-flash")
    
    # Decode base64 image
    image_data = base64.b64decode(image_base64)
    
    # Create image part for Gemini
    image_part = {
        "mime_type": "image/png",
        "data": image_data
    }
    
    # Generate response
    response = model.generate_content([prompt, image_part])
    
    # Parse JSON response
    response_text = response.text.strip()
    
    # Remove markdown code blocks if present
    if response_text.startswith("```"):
        lines = response_text.split("\n")
        response_text = "\n".join(lines[1:-1])
    
    try:
        result = json.loads(response_text)
        return result
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Gemini response: {response_text}")
        raise ValueError(f"Invalid JSON response from Gemini: {e}")


def regenerate_with_gemini(remaining_data: List[Dict], deleted_ids: List[str]) -> List[Dict]:
    """Regenerate summary with Gemini after deletions"""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY not configured")
    
    # Format data for prompt
    remaining_str = json.dumps(remaining_data, indent=2)
    deleted_str = json.dumps(deleted_ids)
    
    # Create the prompt
    prompt = REGENERATE_PROMPT.format(
        remaining_data=remaining_str,
        deleted_ids=deleted_str
    )
    
    # Configure Gemini model  
    model = genai.GenerativeModel("gemini-2.0-flash")
    
    # Generate response
    response = model.generate_content(prompt)
    
    # Parse JSON response
    response_text = response.text.strip()
    
    # Remove markdown code blocks if present
    if response_text.startswith("```"):
        lines = response_text.split("\n")
        response_text = "\n".join(lines[1:-1])
    
    try:
        result = json.loads(response_text)
        return result
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Gemini response: {response_text}")
        raise ValueError(f"Invalid JSON response from Gemini: {e}")


@app.route("/api/analyze", methods=["POST"])
def analyze():
    """
    Analyze a screenshot and extract structured information
    
    Input:
    {
        "image": "base64_string",
        "session_id": "uuid",
        "existing_entities": [...]
    }
    
    Output:
    {
        "raw_text": "extracted text...",
        "entity": {
            "type": "hotel",
            "is_new": true/false,
            "merge_with_id": "uuid or null",
            "data": {...}
        }
    }
    """
    try:
        # Parse and validate request
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        req = AnalyzeRequest(**data)
        
        # Convert existing entities to dict format for Gemini
        existing = [
            {"id": e.id, "type": e.type, "data": e.data}
            for e in req.existing_entities
        ]
        
        # Analyze with Gemini
        result = analyze_with_gemini(req.image, existing)
        
        return jsonify(result)
        
    except ValidationError as e:
        logger.error(f"Validation error: {e}")
        return jsonify({"error": "Invalid request", "details": e.errors()}), 400
    except ValueError as e:
        logger.error(f"Value error: {e}")
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/api/regenerate", methods=["POST"])
def regenerate():
    """
    Regenerate summary after deletions
    
    Input:
    {
        "session_id": "uuid",
        "deleted_ids": ["uuid1", "uuid2"],
        "remaining_screenshots": [...]
    }
    
    Output:
    {
        "summary": [
            {
                "entity_type": "hotel",
                "data": {...}
            }
        ]
    }
    """
    try:
        # Parse and validate request
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        req = RegenerateRequest(**data)
        
        # Convert remaining screenshots to dict format
        remaining = [
            {"id": s.id, "raw_text": s.raw_text, "data": s.data}
            for s in req.remaining_screenshots
        ]
        
        # Regenerate with Gemini
        result = regenerate_with_gemini(remaining, req.deleted_ids)
        
        return jsonify({"summary": result})
        
    except ValidationError as e:
        logger.error(f"Validation error: {e}")
        return jsonify({"error": "Invalid request", "details": e.errors()}), 400
    except ValueError as e:
        logger.error(f"Value error: {e}")
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/api/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "ok",
        "gemini_configured": bool(GEMINI_API_KEY)
    })


# For local development
if __name__ == "__main__":
    app.run(debug=True, port=5000)
