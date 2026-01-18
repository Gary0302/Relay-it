import { NextRequest, NextResponse } from 'next/server';

export const runtime = 'edge';

interface AnalyzeRequest {
    image: string;
}

interface Entity {
    type: string;
    title: string | null;
    attributes: Record<string, string>;
}

interface AnalyzeResponse {
    rawText: string;
    summary: string;
    category: string;
    entities: Entity[];
    suggestedNotebookTitle: string | null;
}

const FALLBACK_RESPONSE: AnalyzeResponse = {
    rawText: '',
    summary: '',
    category: 'other',
    entities: [],
    suggestedNotebookTitle: null,
};

async function analyzeScreenshot(imageData: string): Promise<AnalyzeResponse> {
    const apiKey = process.env.GEMINI_API_KEY;

    if (!apiKey) {
        console.warn('GEMINI_API_KEY not set, returning fallback response');
        return FALLBACK_RESPONSE;
    }

    console.log('API key present, calling Gemini...');

    try {
        // Strip data URL prefix if present
        const base64Data = imageData.includes(',')
            ? imageData.split(',')[1]
            : imageData;

        const prompt = `You are an intelligent screenshot analyzer for a notebook app. Analyze this screenshot and extract structured information.

YOUR TASK:
1. Perform OCR to extract ALL visible text
2. Write a 1-3 sentence summary of what the user is viewing or deciding on
3. Categorize the screenshot into ONE category
4. Extract important entities (items, products, hotels, jobs, articles, etc.)
5. Suggest a notebook title if the context is clear

STRICT OUTPUT FORMAT (JSON ONLY):
{
  "rawText": "full OCR text extracted from screenshot",
  "summary": "1-3 sentence description of what this screenshot shows",
  "category": "trip-planning" | "shopping" | "job-search" | "research" | "content-writing" | "productivity" | "other",
  "entities": [
    {
      "type": "hotel" | "product" | "job" | "article" | "generic" | etc,
      "title": "main name or title",
      "attributes": {
        "key1": "value1",
        "key2": "value2"
      }
    }
  ],
  "suggestedNotebookTitle": "descriptive title for a notebook containing this screenshot, or null"
}

RULES:
- Return ONLY valid JSON, no markdown, no explanations
- If uncertain about summary, use empty string ""
- If no clear category, use "other"
- If no entities found, use empty array []
- If no clear notebook title, use null
- For entities: extract practical attributes (price, rating, location, url, date, company, salary, author, etc.)
- Choose the most specific entity type possible

EXAMPLES:

Hotel listing:
{
  "rawText": "Hotel Deluxe\\n5 stars\\n$299/night\\nSan Francisco, CA",
  "summary": "User is browsing hotel options in San Francisco with pricing and ratings.",
  "category": "trip-planning",
  "entities": [
    {
      "type": "hotel",
      "title": "Hotel Deluxe",
      "attributes": {
        "price": "$299/night",
        "rating": "5 stars",
        "location": "San Francisco, CA"
      }
    }
  ],
  "suggestedNotebookTitle": "San Francisco Hotels"
}

Product page:
{
  "rawText": "MacBook Pro M3\\n$1999\\n16GB RAM\\n512GB SSD",
  "summary": "User is viewing a MacBook Pro M3 laptop configuration.",
  "category": "shopping",
  "entities": [
    {
      "type": "product",
      "title": "MacBook Pro M3",
      "attributes": {
        "price": "$1999",
        "ram": "16GB",
        "storage": "512GB SSD"
      }
    }
  ],
  "suggestedNotebookTitle": "MacBook Comparisons"
}

Job posting:
{
  "rawText": "Senior Software Engineer\\nGoogle\\n$180k-$250k\\nMountain View, CA",
  "summary": "User is viewing a senior software engineering position at Google.",
  "category": "job-search",
  "entities": [
    {
      "type": "job",
      "title": "Senior Software Engineer",
      "attributes": {
        "company": "Google",
        "salary": "$180k-$250k",
        "location": "Mountain View, CA"
      }
    }
  ],
  "suggestedNotebookTitle": "FAANG Job Search"
}

NOW ANALYZE THE PROVIDED SCREENSHOT AND RETURN ONLY THE JSON RESPONSE.`;

        const requestBody = {
            contents: [
                {
                    role: 'user',
                    parts: [
                        { text: prompt },
                        {
                            inlineData: {
                                mimeType: 'image/png',
                                data: base64Data,
                            },
                        },
                    ],
                },
            ],
            generationConfig: {
                temperature: 0.2,
                responseMimeType: 'application/json',
            },
        };

        const response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(requestBody),
            }
        );

        if (!response.ok) {
            const errorBody = await response.text();
            console.error(`Gemini API error: ${response.status} ${response.statusText}`, errorBody);
            return FALLBACK_RESPONSE;
        }

        const data = await response.json();
        const textContent = data.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!textContent) {
            console.error('No content returned from Gemini');
            return FALLBACK_RESPONSE;
        }

        let parsed: AnalyzeResponse;
        try {
            parsed = JSON.parse(textContent);
        } catch (e) {
            console.error('Failed to parse Gemini response as JSON:', e);
            return FALLBACK_RESPONSE;
        }

        // Validate and normalize response
        const result: AnalyzeResponse = {
            rawText: parsed.rawText || '',
            summary: parsed.summary || '',
            category: parsed.category || 'other',
            entities: Array.isArray(parsed.entities) ? parsed.entities : [],
            suggestedNotebookTitle: parsed.suggestedNotebookTitle || null,
        };

        return result;
    } catch (error) {
        console.error('Error in analyzeScreenshot:', error);
        return FALLBACK_RESPONSE;
    }
}

export async function POST(request: NextRequest) {
    try {
        console.log('=== Analyze endpoint called ===');
        const body: AnalyzeRequest = await request.json();
        console.log('Request body received, image length:', body.image?.length || 0);

        if (!body.image) {
            console.log('ERROR: Missing image field');
            return NextResponse.json(
                { error: 'Missing required field: image' },
                {
                    status: 400,
                    headers: {
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'POST, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type',
                    }
                }
            );
        }

        console.log('Calling analyzeScreenshot...');
        const result = await analyzeScreenshot(body.image);
        console.log('Result:', JSON.stringify(result, null, 2));

        return NextResponse.json(result, {
            status: 200,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
            }
        });
    } catch (error) {
        console.error('Request handling error:', error);
        return NextResponse.json(FALLBACK_RESPONSE, {
            status: 200,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
            }
        });
    }
}

export async function OPTIONS(request: NextRequest) {
    return new NextResponse(null, {
        status: 200,
        headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        },
    });
}