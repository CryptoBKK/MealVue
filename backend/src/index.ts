type Env = {
  DEFAULT_PROVIDER?: string;
  CLOUDFLARE_MODEL?: string;
  AI?: AiBinding;
  GEMINI_MODEL?: string;
  GEMINI_API_KEY?: string;
  OPENROUTER_MODEL?: string;
  OPENROUTER_API_KEY?: string;
  MEALVUE_CLIENT_TOKEN?: string;
  ADMIN_TOKEN?: string;
  USAGE_COUNTER?: DurableObjectNamespace;
};

type AnalyzeRequest = {
  mode?: "text" | "image";
  description?: string;
  imageBase64?: string;
  mimeType?: string;
  provider?: "cloudflare" | "gemini" | "openrouter";
};

type ExecutionContext = {
  waitUntil(promise: Promise<unknown>): void;
};

type AiBinding = {
  run(model: string, input: Record<string, unknown>): Promise<unknown>;
};

type DurableObjectNamespace = {
  idFromName(name: string): DurableObjectId;
  get(id: DurableObjectId): DurableObjectStub;
};

type DurableObjectId = unknown;

type DurableObjectStub = {
  fetch(input: string | Request, init?: RequestInit): Promise<Response>;
};

type DurableObjectState = {
  storage: {
    get<T = unknown>(key: string): Promise<T | undefined>;
    put<T = unknown>(key: string, value: T): Promise<void>;
    delete(key: string): Promise<void>;
  };
};

type ProviderUsage = {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  estimatedCostUsd: number;
};

type AnalysisResult = {
  payload: unknown;
  usage: ProviderUsage;
};

type UsageCounter = {
  requests: number;
  successes: number;
  failures: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  estimatedCostUsd: number;
  totalDurationMs: number;
};

type ProviderCounter = UsageCounter & {
  provider: string;
  model: string;
};

type UsageEvent = {
  timestamp: string;
  provider: string;
  model: string;
  mode: string;
  status: "success" | "error";
  durationMs: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  estimatedCostUsd: number;
  error?: string;
};

type UsageSnapshot = {
  updatedAt: string;
  totals: UsageCounter;
  daily: Record<string, UsageCounter>;
  providers: Record<string, ProviderCounter>;
  recentEvents: UsageEvent[];
};

const usageKey = "usage:v1";

const nutritionSchemaPrompt = `Return ONLY one valid JSON object. Do not include markdown, headings, explanations, numbered steps, or commentary.
{
  "food_name": "specific food name",
  "estimated_quantity": "serving size",
  "calories": 450,
  "protein_g": 28.0,
  "carbs_g": 45.0,
  "fat_g": 14.0,
  "fiber_g": 3.0,
  "sodium_mg": 950,
  "potassium_mg": 540,
  "phosphorus_mg": 320,
  "confidence": "medium",
  "notes": "brief assumptions",
  "kidney_warning": "brief warning if needed, otherwise empty string",
  "heart_warning": "brief warning if needed, otherwise empty string",
  "sodium_warning": "brief warning if sodium is clearly high, otherwise empty string",
  "potassium_warning": "brief warning if potassium is clearly high, otherwise empty string",
  "phosphorus_warning": "brief warning if phosphorus is clearly high, otherwise empty string"
}

All numeric fields must be numbers. Estimate sodium, potassium, and phosphorus in milligrams.

If unsure, use reasonable estimates and set "confidence" to "low" or "medium".`;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        ok: true,
        service: "mealvue-ai-backend",
        usageStore: Boolean(env.USAGE_COUNTER)
      });
    }

    if (request.method === "GET" && url.pathname === "/admin") {
      const authError = authorizeAdmin(request, env);
      if (authError) return authError;
      return html(adminDashboardHtml());
    }

    if (request.method === "GET" && url.pathname === "/admin/usage") {
      const authError = authorizeAdmin(request, env);
      if (authError) return authError;
      return json(await getUsageSnapshot(env));
    }

    if (request.method === "POST" && url.pathname === "/admin/usage/reset") {
      const authError = authorizeAdmin(request, env);
      if (authError) return authError;
      await resetUsage(env);
      return json({ ok: true });
    }

    if (request.method === "POST" && url.pathname === "/v1/analyze") {
      const authError = authorize(request, env);
      if (authError) return authError;

      let body: AnalyzeRequest;
      try {
        body = await request.json();
      } catch {
        return json({ error: "Invalid JSON request body." }, 400);
      }

      const startedAt = Date.now();
      const provider = body.provider ?? (env.DEFAULT_PROVIDER as AnalyzeRequest["provider"]) ?? "cloudflare";
      const model = modelForProvider(provider, env);

      try {
        const result = await analyzeWithProvider(provider, body, env);

        ctx.waitUntil(recordUsage(env, {
          timestamp: new Date().toISOString(),
          provider,
          model,
          mode: body.mode || "text",
          status: "success",
          durationMs: Date.now() - startedAt,
          ...result.usage
        }));

        return json(result.payload);
      } catch (error) {
        const message = error instanceof Error ? error.message : "AI analysis failed.";
        ctx.waitUntil(recordUsage(env, {
          timestamp: new Date().toISOString(),
          provider,
          model,
          mode: body.mode || "text",
          status: "error",
          durationMs: Date.now() - startedAt,
          inputTokens: 0,
          outputTokens: 0,
          totalTokens: 0,
          estimatedCostUsd: 0,
          error: message
        }));
        return json({ error: message }, 502);
      }
    }

    return json({ error: "Not found." }, 404);
  }
};

function authorizeAdmin(request: Request, env: Env): Response | null {
  const token = env.ADMIN_TOKEN || env.MEALVUE_CLIENT_TOKEN;
  if (!token) return null;

  const authHeader = request.headers.get("authorization");
  const urlToken = new URL(request.url).searchParams.get("token");
  if (authHeader === `Bearer ${token}` || urlToken === token) return null;

  return html(adminLoginHtml(), 401);
}

function authorize(request: Request, env: Env): Response | null {
  if (!env.MEALVUE_CLIENT_TOKEN) return null;

  const expected = `Bearer ${env.MEALVUE_CLIENT_TOKEN}`;
  if (request.headers.get("authorization") === expected) return null;

  return json({ error: "Unauthorized." }, 401);
}

async function analyzeWithProvider(provider: AnalyzeRequest["provider"], body: AnalyzeRequest, env: Env): Promise<AnalysisResult> {
  if (provider === "openrouter") return analyzeWithOpenRouter(body, env);
  if (provider === "gemini") return analyzeWithGemini(body, env);
  return analyzeWithCloudflare(body, env);
}

async function analyzeWithCloudflare(body: AnalyzeRequest, env: Env): Promise<AnalysisResult> {
  if (!env.AI) throw new Error("Cloudflare Workers AI binding is not configured.");

  const model = modelForProvider("cloudflare", env);
  const prompt = promptFor(body);
  const input: Record<string, unknown> = {
    prompt: `You are MealVue's nutrition analysis engine. Return only strict JSON matching the requested schema. Do not include markdown, code fences, or commentary.\n\n${prompt}`,
    max_tokens: 700,
    temperature: 0.1
  };

  if (body.mode === "image" && body.imageBase64) {
    const binaryString = atob(body.imageBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    input.image = [...bytes];
  }

  const decoded = await env.AI.run(model, input);
  let content = cloudflareResponseText(decoded);
  const usage = cloudflareUsage(decoded);
  const inputTokens = usage.inputTokens || estimateTokens(prompt);
  let outputTokens = usage.outputTokens || estimateTokens(content);
  let payload: unknown;

  try {
    payload = parseNutritionJSON(content);
  } catch {
    const repaired = await repairCloudflareNutritionJSON(content, env);
    content = repaired.content;
    outputTokens += repaired.outputTokens;
    payload = repaired.payload;
  }

  return {
    payload,
    usage: {
      inputTokens,
      outputTokens,
      totalTokens: inputTokens + outputTokens,
      estimatedCostUsd: estimateCost("cloudflare", model, inputTokens, outputTokens)
    }
  };
}

async function repairCloudflareNutritionJSON(rawContent: string, env: Env): Promise<{ content: string; outputTokens: number; payload: unknown }> {
  if (!env.AI) throw new Error("Cloudflare Workers AI binding is not configured.");

  const model = modelForProvider("cloudflare", env);
  const repairPrompt = `Convert the following food analysis into ONLY the strict JSON object schema below.
Do not include markdown, code fences, headings, or explanations.

Schema:
${nutritionSchemaPrompt}

Food analysis to convert:
${rawContent.slice(0, 4000)}`;

  const decoded = await env.AI.run(model, {
    prompt: repairPrompt,
    max_tokens: 700,
    temperature: 0
  });

  const content = cloudflareResponseText(decoded);
  return {
    content,
    outputTokens: cloudflareUsage(decoded).outputTokens || estimateTokens(content),
    payload: parseNutritionJSON(content)
  };
}

async function analyzeWithGemini(body: AnalyzeRequest, env: Env): Promise<AnalysisResult> {
  if (!env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY is not configured.");

  const model = modelForProvider("gemini", env);
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const prompt = promptFor(body);

  const parts: unknown[] = [{ text: prompt }];
  if (body.mode === "image" && body.imageBase64) {
    parts.unshift({
      inline_data: {
        mime_type: body.mimeType || "image/jpeg",
        data: body.imageBase64
      }
    });
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": env.GEMINI_API_KEY
    },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: {
        response_mime_type: "application/json",
        max_output_tokens: 700
      }
    })
  });

  const text = await response.text();
  if (!response.ok) throw new Error(providerError("Gemini", response.status, text));

  const decoded = JSON.parse(text);
  const content = decoded?.candidates?.[0]?.content?.parts
    ?.map((part: { text?: string }) => part.text ?? "")
    ?.join("\n");

  const inputTokens = numeric(decoded?.usageMetadata?.promptTokenCount);
  const outputTokens = numeric(decoded?.usageMetadata?.candidatesTokenCount);
  const totalTokens = numeric(decoded?.usageMetadata?.totalTokenCount) || inputTokens + outputTokens;

  return {
    payload: parseNutritionJSON(content || ""),
    usage: {
      inputTokens,
      outputTokens,
      totalTokens,
      estimatedCostUsd: estimateCost("gemini", model, inputTokens, outputTokens)
    }
  };
}

async function analyzeWithOpenRouter(body: AnalyzeRequest, env: Env): Promise<AnalysisResult> {
  if (!env.OPENROUTER_API_KEY) throw new Error("OPENROUTER_API_KEY is not configured.");

  const model = modelForProvider("openrouter", env);
  const content: unknown[] = [{ type: "text", text: promptFor(body) }];
  if (body.mode === "image" && body.imageBase64) {
    content.push({
      type: "image_url",
      image_url: {
        url: `data:${body.mimeType || "image/jpeg"};base64,${body.imageBase64}`
      }
    });
  }

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${env.OPENROUTER_API_KEY}`,
      "content-type": "application/json",
      "x-title": "MealVue"
    },
    body: JSON.stringify({
      model,
      max_tokens: 700,
      response_format: { type: "json_object" },
      usage: { include: true },
      provider: {
        sort: "latency",
        allow_fallbacks: true,
        require_parameters: false
      },
      messages: [{ role: "user", content }]
    })
  });

  const text = await response.text();
  if (!response.ok) throw new Error(providerError("OpenRouter", response.status, text));

  const decoded = JSON.parse(text);
  const contentText = decoded?.choices?.[0]?.message?.content ?? "";
  const inputTokens = numeric(decoded?.usage?.prompt_tokens);
  const outputTokens = numeric(decoded?.usage?.completion_tokens);
  const totalTokens = numeric(decoded?.usage?.total_tokens) || inputTokens + outputTokens;
  const returnedCost = numeric(decoded?.usage?.cost);

  return {
    payload: parseNutritionJSON(contentText),
    usage: {
      inputTokens,
      outputTokens,
      totalTokens,
      estimatedCostUsd: returnedCost || estimateCost("openrouter", model, inputTokens, outputTokens)
    }
  };
}

function promptFor(body: AnalyzeRequest): string {
  const userDescription = body.description?.trim();
  if (body.mode === "text") {
    return `Analyze this food description: "${userDescription || "unspecified food"}"

Return final nutrition estimates as strict JSON only.

${nutritionSchemaPrompt}`;
  }

  if (userDescription) {
    return `Analyze this food image. The user correction/context is: "${userDescription}"

Return final nutrition estimates as strict JSON only.

${nutritionSchemaPrompt}`;
  }

  return `Analyze this food image.

Return final nutrition estimates as strict JSON only.

${nutritionSchemaPrompt}`;
}

function imageDataUrl(body: AnalyzeRequest): string {
  const imageBase64 = body.imageBase64 || "";
  if (!imageBase64.startsWith("data:")) return imageBase64;
  return imageBase64.slice(imageBase64.indexOf(",") + 1);
}

function cloudflareResponseText(decoded: unknown): string {
  if (typeof decoded === "string") return decoded;
  if (!decoded || typeof decoded !== "object") return "";

  const value = decoded as {
    response?: unknown;
    result?: unknown;
    usage?: unknown;
    choices?: Array<{ message?: { content?: unknown }; text?: unknown }>;
  };

  if (typeof value.response === "string") return value.response;
  if (value.response && typeof value.response === "object") return JSON.stringify(value.response);
  if (typeof value.result === "string") return value.result;
  if (value.result && typeof value.result === "object") return JSON.stringify(value.result);
  const firstChoice = value.choices?.[0];
  if (typeof firstChoice?.message?.content === "string") return firstChoice.message.content;
  if (typeof firstChoice?.text === "string") return firstChoice.text;

  return JSON.stringify(decoded);
}

function cloudflareUsage(decoded: unknown): { inputTokens: number; outputTokens: number } {
  if (!decoded || typeof decoded !== "object") {
    return { inputTokens: 0, outputTokens: 0 };
  }

  const usage = (decoded as { usage?: Record<string, unknown> }).usage;
  return {
    inputTokens: numeric(usage?.prompt_tokens),
    outputTokens: numeric(usage?.completion_tokens)
  };
}

function parseNutritionJSON(text: string): unknown {
  const jsonText = firstBalancedJSONObject(text);
  if (!jsonText) {
    throw new Error(`AI returned no valid nutrition JSON: ${text.slice(0, 240)}`);
  }

  return JSON.parse(jsonText);
}

function firstBalancedJSONObject(text: string): string | null {
  const start = text.indexOf("{");
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = start; index < text.length; index += 1) {
    const char = text[index];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
      inString = true;
      continue;
    }

    if (char === "{") depth += 1;
    if (char === "}") depth -= 1;

    if (depth === 0) return text.slice(start, index + 1);
  }

  return null;
}

function providerError(provider: string, status: number, body: string): string {
  if (status === 401 || status === 403) return `${provider} API key was rejected.`;
  if (status === 402) return `${provider} account needs credits or billing.`;
  if (status === 404) return `${provider} model was not found.`;
  if (status === 429) return `${provider} is rate limited or out of quota.`;
  if (status >= 500) return `${provider} is temporarily unavailable.`;
  return `${provider} error ${status}: ${body.slice(0, 240)}`;
}

function modelForProvider(provider: AnalyzeRequest["provider"], env: Env): string {
  if (provider === "cloudflare") return env.CLOUDFLARE_MODEL || "@cf/meta/llama-3.2-11b-vision-instruct";
  if (provider === "openrouter") return env.OPENROUTER_MODEL || "openrouter/free";
  return env.GEMINI_MODEL || "gemini-2.5-flash";
}

function numeric(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function estimateCost(provider: string, model: string, inputTokens: number, outputTokens: number): number {
  const key = `${provider}:${model}`;
  const price = pricingUsdPerMillionTokens[key] ?? defaultPricingUsdPerMillionTokens[provider];
  if (!price) return 0;
  return ((inputTokens * price.input) + (outputTokens * price.output)) / 1_000_000;
}

function estimateTokens(text: string): number {
  return Math.max(1, Math.ceil(text.length / 4));
}

const pricingUsdPerMillionTokens: Record<string, { input: number; output: number }> = {
  "cloudflare:@cf/meta/llama-3.2-11b-vision-instruct": { input: 0.049, output: 0.68 },
  "gemini:gemini-2.5-flash": { input: 0.30, output: 2.50 },
  "openrouter:openrouter/free": { input: 0, output: 0 }
};

const defaultPricingUsdPerMillionTokens: Record<string, { input: number; output: number }> = {
  cloudflare: { input: 0.049, output: 0.68 },
  gemini: { input: 0.30, output: 2.50 },
  openrouter: { input: 0, output: 0 }
};

async function recordUsage(env: Env, event: UsageEvent): Promise<void> {
  if (!env.USAGE_COUNTER) return;
  await usageStub(env).fetch("https://usage/event", {
    method: "POST",
    body: JSON.stringify(event)
  });
}

async function getUsageSnapshot(env: Env): Promise<UsageSnapshot> {
  if (!env.USAGE_COUNTER) return emptySnapshot();
  const response = await usageStub(env).fetch("https://usage/snapshot");
  return response.json();
}

async function resetUsage(env: Env): Promise<void> {
  if (!env.USAGE_COUNTER) return;
  await usageStub(env).fetch("https://usage/reset", { method: "POST" });
}

function usageStub(env: Env): DurableObjectStub {
  if (!env.USAGE_COUNTER) throw new Error("USAGE_COUNTER is not configured.");
  return env.USAGE_COUNTER.get(env.USAGE_COUNTER.idFromName("global"));
}

function applyUsageEvent(counter: UsageCounter, event: UsageEvent): void {
  counter.requests += 1;
  if (event.status === "success") counter.successes += 1;
  if (event.status === "error") counter.failures += 1;
  counter.inputTokens += event.inputTokens;
  counter.outputTokens += event.outputTokens;
  counter.totalTokens += event.totalTokens;
  counter.estimatedCostUsd += event.estimatedCostUsd;
  counter.totalDurationMs += event.durationMs;
}

function emptySnapshot(): UsageSnapshot {
  return {
    updatedAt: new Date(0).toISOString(),
    totals: emptyCounter(),
    daily: {},
    providers: {},
    recentEvents: []
  };
}

function emptyCounter(): UsageCounter {
  return {
    requests: 0,
    successes: 0,
    failures: 0,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    estimatedCostUsd: 0,
    totalDurationMs: 0
  };
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

export class UsageCounterObject {
  constructor(private state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/snapshot") {
      return json(await this.snapshot());
    }

    if (request.method === "POST" && url.pathname === "/event") {
      const event = await request.json() as UsageEvent;
      const snapshot = await this.snapshot();
      snapshot.updatedAt = event.timestamp;
      applyUsageEvent(snapshot.totals, event);

      const day = event.timestamp.slice(0, 10);
      snapshot.daily[day] ??= emptyCounter();
      applyUsageEvent(snapshot.daily[day], event);

      const providerKey = `${event.provider}:${event.model}`;
      snapshot.providers[providerKey] ??= {
        ...emptyCounter(),
        provider: event.provider,
        model: event.model
      };
      applyUsageEvent(snapshot.providers[providerKey], event);

      snapshot.recentEvents = [event, ...snapshot.recentEvents].slice(0, 50);
      await this.state.storage.put(usageKey, snapshot);
      return json({ ok: true });
    }

    if (request.method === "POST" && url.pathname === "/reset") {
      await this.state.storage.delete(usageKey);
      return json({ ok: true });
    }

    return json({ error: "Not found." }, 404);
  }

  private async snapshot(): Promise<UsageSnapshot> {
    return (await this.state.storage.get<UsageSnapshot>(usageKey)) ?? emptySnapshot();
  }
}

function adminLoginHtml(): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MealVue Usage</title>
  <style>
    body { margin: 0; font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #17201b; background: #f7f4ee; }
    main { max-width: 420px; margin: 14vh auto; padding: 0 20px; }
    h1 { font-size: 28px; margin: 0 0 16px; }
    form { display: grid; gap: 12px; }
    input, button { font: inherit; border-radius: 8px; border: 1px solid #b9b1a3; padding: 10px 12px; }
    button { border-color: #1d5f46; background: #1d5f46; color: white; cursor: pointer; }
  </style>
</head>
<body>
  <main>
    <h1>MealVue Usage</h1>
    <form onsubmit="event.preventDefault(); location.href='/admin?token=' + encodeURIComponent(document.querySelector('input').value)">
      <input type="password" autocomplete="current-password" placeholder="Admin token" autofocus>
      <button type="submit">Open Dashboard</button>
    </form>
  </main>
</body>
</html>`;
}

function adminDashboardHtml(): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MealVue Usage</title>
  <style>
    :root { color-scheme: light; --ink: #17201b; --muted: #65716b; --line: #d8d1c4; --green: #1d5f46; --blue: #255b84; --red: #9d352f; --bg: #f7f4ee; --panel: #fffdf8; }
    * { box-sizing: border-box; }
    body { margin: 0; font: 14px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: var(--ink); background: var(--bg); }
    header { display: flex; align-items: end; justify-content: space-between; gap: 20px; padding: 28px 32px 18px; border-bottom: 1px solid var(--line); background: var(--panel); }
    h1 { margin: 0; font-size: 28px; line-height: 1.1; letter-spacing: 0; }
    .subtle { color: var(--muted); }
    main { padding: 24px 32px 40px; display: grid; gap: 24px; }
    .metrics { display: grid; grid-template-columns: repeat(6, minmax(130px, 1fr)); gap: 12px; }
    .metric, section { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; }
    .metric { padding: 14px; min-height: 86px; }
    .metric span { display: block; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    .metric strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.1; overflow-wrap: anywhere; }
    section { overflow: hidden; }
    section h2 { margin: 0; padding: 14px 16px; font-size: 15px; border-bottom: 1px solid var(--line); background: #faf8f3; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #ebe5d9; white-space: nowrap; }
    th { color: var(--muted); font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; }
    tr:last-child td { border-bottom: 0; }
    .ok { color: var(--green); font-weight: 700; }
    .err { color: var(--red); font-weight: 700; }
    .toolbar { display: flex; align-items: center; justify-content: flex-end; gap: 10px; }
    button { border: 1px solid var(--green); background: var(--green); color: white; border-radius: 8px; padding: 9px 12px; font: inherit; cursor: pointer; }
    button.secondary { color: var(--green); background: transparent; }
    .empty { padding: 18px 16px; color: var(--muted); }
    .wide { overflow-x: auto; }
    @media (max-width: 960px) { header { align-items: start; flex-direction: column; padding: 22px 18px 16px; } main { padding: 18px; } .metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); } .metric strong { font-size: 20px; } }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>MealVue Usage</h1>
      <div id="updated" class="subtle">Loading usage data</div>
    </div>
    <div class="toolbar">
      <button class="secondary" onclick="loadUsage()">Refresh</button>
      <button onclick="resetUsage()">Reset</button>
    </div>
  </header>
  <main>
    <div class="metrics" id="metrics"></div>
    <section>
      <h2>Providers</h2>
      <div class="wide"><table id="providers"></table></div>
    </section>
    <section>
      <h2>Daily</h2>
      <div class="wide"><table id="daily"></table></div>
    </section>
    <section>
      <h2>Recent Events</h2>
      <div class="wide"><table id="events"></table></div>
    </section>
  </main>
  <script>
    const token = new URLSearchParams(location.search).get('token') || '';
    const suffix = token ? '?token=' + encodeURIComponent(token) : '';
    const money = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 5 });
    const number = new Intl.NumberFormat('en-US');

    async function loadUsage() {
      const res = await fetch('/admin/usage' + suffix, { cache: 'no-store' });
      if (res.status === 401) { location.href = '/admin'; return; }
      const data = await res.json();
      render(data);
    }

    async function resetUsage() {
      if (!confirm('Reset MealVue usage counters?')) return;
      await fetch('/admin/usage/reset' + suffix, { method: 'POST' });
      await loadUsage();
    }

    function render(data) {
      const totals = data.totals || {};
      document.getElementById('updated').textContent = data.updatedAt && !data.updatedAt.startsWith('1970-') ? 'Updated ' + new Date(data.updatedAt).toLocaleString() : 'No usage recorded yet';
      document.getElementById('metrics').innerHTML = [
        metric('Requests', number.format(totals.requests || 0)),
        metric('Success', number.format(totals.successes || 0)),
        metric('Failures', number.format(totals.failures || 0)),
        metric('Tokens', number.format(totals.totalTokens || 0)),
        metric('Est. AI Cost', money.format(totals.estimatedCostUsd || 0)),
        metric('Avg Latency', avgLatency(totals))
      ].join('');
      renderTable('providers', ['Provider', 'Model', 'Requests', 'Success', 'Failures', 'Tokens', 'Est. Cost'], Object.values(data.providers || {}).map(row => [
        row.provider, row.model, number.format(row.requests || 0), number.format(row.successes || 0), number.format(row.failures || 0), number.format(row.totalTokens || 0), money.format(row.estimatedCostUsd || 0)
      ]));
      renderTable('daily', ['Date', 'Requests', 'Success', 'Failures', 'Tokens', 'Est. Cost', 'Avg Latency'], Object.entries(data.daily || {}).sort((a, b) => b[0].localeCompare(a[0])).map(([date, row]) => [
        date, number.format(row.requests || 0), number.format(row.successes || 0), number.format(row.failures || 0), number.format(row.totalTokens || 0), money.format(row.estimatedCostUsd || 0), avgLatency(row)
      ]));
      renderTable('events', ['Time', 'Status', 'Provider', 'Model', 'Mode', 'Tokens', 'Est. Cost', 'Latency', 'Error'], (data.recentEvents || []).map(event => [
        new Date(event.timestamp).toLocaleString(), status(event.status), event.provider, event.model, event.mode, number.format(event.totalTokens || 0), money.format(event.estimatedCostUsd || 0), (event.durationMs || 0) + ' ms', event.error || ''
      ]));
    }

    function metric(label, value) {
      return '<div class="metric"><span>' + escapeHtml(label) + '</span><strong>' + escapeHtml(value) + '</strong></div>';
    }

    function renderTable(id, headings, rows) {
      const el = document.getElementById(id);
      if (!rows.length) {
        el.outerHTML = '<div id="' + id + '" class="empty">No records yet</div>';
        return;
      }
      if (el.tagName !== 'TABLE') {
        const table = document.createElement('table');
        table.id = id;
        el.replaceWith(table);
      }
      document.getElementById(id).innerHTML = '<thead><tr>' + headings.map(h => '<th>' + escapeHtml(h) + '</th>').join('') + '</tr></thead><tbody>' + rows.map(row => '<tr>' + row.map(cell => '<td>' + renderCell(cell) + '</td>').join('') + '</tr>').join('') + '</tbody>';
    }

    function status(value) {
      const cls = value === 'success' ? 'ok' : 'err';
      return '<span class="' + cls + '">' + escapeHtml(value) + '</span>';
    }

    function avgLatency(row) {
      return row && row.requests ? Math.round((row.totalDurationMs || 0) / row.requests) + ' ms' : '0 ms';
    }

    function escapeHtml(value) {
      return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
    }

    function renderCell(value) {
      const text = String(value);
      if (text.startsWith('<span class="ok">') || text.startsWith('<span class="err">')) return text;
      return escapeHtml(text);
    }

    loadUsage();
  </script>
</body>
</html>`;
}
