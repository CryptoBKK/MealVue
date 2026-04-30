# MealVue

MealVue is an iOS SwiftUI app for meal logging with optional AI analysis and built-in kidney and heart health guidance.

## Features

- Photo meal logging with manual review before save
- Text meal description analysis
- Daily log and history views backed by SwiftData
- Startup loading screen instead of a blank first-launch white screen
- AI provider support for:
  - Anthropic
  - Google Gemini
  - OpenAI
  - OpenRouter
- Live model pickers for Gemini, OpenAI, and OpenRouter
- Optional kidney health checker
- Optional heart health checker
- CKD stage selector with stage-aware default targets
- Daily totals for:
  - Calories
  - Protein
  - Sodium
  - Potassium
  - Phosphorus
- Red highlighting when tracked daily targets are exceeded
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
7. Optionally enter:
   - sex
   - age
   - height
   - weight
   - CKD stage
8. Review or override the daily targets for:
   - protein
   - sodium
   - potassium
   - phosphorus

## Notes

- If no API key is configured, the app still supports manual meal entry.
- OpenRouter free models may be temporarily unavailable. The app falls back to `openrouter/free` when possible.
- Health warnings are controlled by the toggles in `Settings`.
- The app displays which provider and model produced each AI analysis result.
- Sodium, potassium, phosphorus, and protein targets can be manually overridden in `Settings`.
- CKD defaults are stage-aware, but they are still reference targets and should not replace clinician guidance or lab-based diet planning.
