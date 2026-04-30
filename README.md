# MealVue

MealVue is an iOS SwiftUI app for meal logging with optional AI analysis and built-in kidney and heart health guidance.

## Features

- Photo meal logging with manual review before save
- Text meal description analysis
- Daily log and history views backed by SwiftData
- AI provider support for:
  - Anthropic
  - Google Gemini
  - OpenAI
  - OpenRouter
- Live model pickers for Gemini, OpenAI, and OpenRouter
- Optional kidney health checker
- Optional heart health checker
- Food and medication reference guidance

## Setup

1. Open the app.
2. Go to `Settings`.
3. Choose an AI provider.
4. Enter that provider's API key.
5. Refresh models if the provider supports live model loading.
6. Optionally enable or disable:
   - `Kidney Health Checker`
   - `Heart Health Checker`

## Notes

- If no API key is configured, the app still supports manual meal entry.
- OpenRouter free models may be temporarily unavailable. The app falls back to `openrouter/free` when possible.
- Health warnings are controlled by the toggles in `Settings`.
- The app displays which provider and model produced each AI analysis result.
