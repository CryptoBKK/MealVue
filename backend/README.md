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
npx wrangler secret put ADMIN_TOKEN
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

- `DEFAULT_PROVIDER=cloudflare`
- `CLOUDFLARE_MODEL=@cf/meta/llama-3.2-11b-vision-instruct`
- `CLOUDFLARE_IMAGE_MODEL_TRIAL_REQUESTS=10`
- `GEMINI_MODEL=gemini-2.5-flash`
- `OPENROUTER_MODEL=openrouter/free`

Use Cloudflare Workers AI for built-in MealVue AI. Keep Gemini/OpenRouter available for fallback or bring-your-own-key tiers.

## Vision Model Candidates (5 Best for Food Analysis)

The backend auto-trials these Cloudflare vision models and picks the fastest with ≥80% success rate:

| # | Model | Strengths | Input Cost | Output Cost |
|---|-------|-----------|------------|-------------|
| 1 | `@cf/meta/llama-4-scout-17b-16e-instruct` | Best accuracy, 17B multimodal, excellent food understanding | $0.270/M | $0.850/M |
| 2 | `@cf/google/gemma-3-12b-it` | Strong multimodal, 128K context, 140+ languages (Thai food!) | $0.345/M | $0.556/M |
| 3 | `@cf/meta/llama-3.2-11b-vision-instruct` | Cheapest vision, decent accuracy, proven | $0.049/M | $0.676/M |
| 4 | `@cf/mistralai/mistral-small-3.1-24b-instruct` | Good quality, moderate cost | $0.351/M | $0.555/M |
| 5 | `@cf/google/gemma-4-26b-a4b-it` | Newest Google, efficient, vision + tool calling | $0.100/M | $0.300/M |

### External Provider Options (via OpenRouter or direct API)

| Model | Best For | Input Cost | Output Cost |
|-------|----------|------------|-------------|
| `gemini-2.5-flash` | Best overall food vision, very fast | $0.30/M | $2.50/M |
| `gemini-2.5-flash-lite` | Cheapest Gemini, still good | $0.10/M | $0.40/M |
| `gpt-4o-mini` | Cheap OpenAI vision | $0.15/M | $0.60/M |
| `claude-haiku-4.5` | Fast Anthropic vision | $1.00/M | $5.00/M |

### Recommendation

- **Free tier**: Use `gemma-4-26b-a4b-it` (cheapest) or `llama-3.2-11b-vision-instruct`
- **Plus tier**: Use `gemma-3-12b-it` or `llama-4-scout-17b-16e-instruct`
- **BYO AI**: Recommend `gemini-2.5-flash` (best accuracy/speed/cost balance for food)

## Usage Dashboard And Image Model Testing

Open:

```text
https://mealvue-ai-backend.cryptobkk.workers.dev/admin
```

Use `ADMIN_TOKEN` as the dashboard password.

For Cloudflare image analysis, the Worker rotates through `CLOUDFLARE_IMAGE_MODELS`. It tests each model for `CLOUDFLARE_IMAGE_MODEL_TRIAL_REQUESTS` image requests, then selects the fastest model with at least an 80% success rate. The dashboard includes a `Model Tests` table with request count, success rate, average latency, failures, tokens, and estimated cost by model/mode.

## Next Backend Tasks

- Add per-user usage tracking in Cloudflare D1 or KV.
- Verify StoreKit subscription status before granting paid-tier usage.
- Add App Attest or DeviceCheck before public launch.
- Add Cloudflare AI Gateway routing/logging.
- Add structured provider fallback: Gemini Flash -> OpenAI small vision model -> OpenRouter.
- Add request size limits and image resizing on the app side.
