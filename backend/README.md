# MealVue AI Backend

Cloudflare Worker backend for built-in MealVue AI analysis.

The iPhone app should eventually call this backend instead of storing AI provider API keys on-device.

## Endpoints

```text
GET  /health
POST /v1/analyze
```

`POST /v1/analyze` accepts:

```json
{
  "mode": "text",
  "description": "one bowl of oatmeal with blueberries",
  "provider": "gemini"
}
```

or:

```json
{
  "mode": "image",
  "imageBase64": "...",
  "mimeType": "image/jpeg",
  "description": "optional correction/context",
  "provider": "gemini"
}
```

## Setup

Install dependencies:

```bash
cd backend
npm install
```

Login to Cloudflare:

```bash
npx wrangler login
```

Set secrets:

```bash
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put OPENROUTER_API_KEY
npx wrangler secret put MEALVUE_CLIENT_TOKEN
```

Run locally:

```bash
npm run dev
```

Deploy:

```bash
npm run deploy
```

## Recommended Defaults

- `DEFAULT_PROVIDER=gemini`
- `GEMINI_MODEL=gemini-2.5-flash`
- `OPENROUTER_MODEL=openrouter/free`

Use Gemini Flash for production cost control, OpenRouter Free Router for internal testing, and add OpenAI fallback later if food recognition quality requires it.

## Next Backend Tasks

- Add per-user usage tracking in Cloudflare D1 or KV.
- Verify StoreKit subscription status before granting paid-tier usage.
- Add App Attest or DeviceCheck before public launch.
- Add Cloudflare AI Gateway routing/logging.
- Add structured provider fallback: Gemini Flash -> OpenAI small vision model -> OpenRouter.
- Add request size limits and image resizing on the app side.

