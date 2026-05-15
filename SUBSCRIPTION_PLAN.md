# MealVue Subscription Plan

MealVue should use Apple in-app purchases for paid access on iOS, specifically auto-renewable subscriptions with StoreKit 2.

## Recommended Tiers

### Free

- Manual food logging.
- Basic daily dashboard.
- Limited history.
- Limited barcode/photo scans.
- Basic kidney and heart guidance.

### Plus

- Unlimited food logging.
- Apple Health write/sync.
- Barcode serving adjustment.
- Dashboard trends.
- Shopping Helper.
- iCloud sync.

### BYO AI

Lower-cost paid tier for users who bring their own AI provider key.

- Everything in Plus.
- User enters their own OpenRouter, Gemini, OpenAI, or Anthropic API key.
- MealVue provides the app UI, logging, Apple Health/iCloud sync, barcode tools, dashboards, and guide features.
- User pays their own AI provider costs directly.
- MealVue does not pay inference costs for this tier.
- Direct AI provider settings should only be visible for BYO AI users or developer/tester mode.

This tier can be priced lower than built-in AI tiers because MealVue is not covering AI usage.

### MealVue AI

Higher-cost paid tier for normal users who want built-in AI with no API setup.

- Everything in Plus.
- Built-in MealVue AI through the MealVue Cloudflare backend.
- No provider API key setup.
- Backend enforces usage limits.
- MealVue pays Cloudflare/provider inference costs.

### Pro

- Everything in MealVue AI.
- Advanced AI analysis.
- Kidney and heart personalization.
- HealthKit lab trend correlations.
- Export reports.
- Priority multi-device/power-user features.

Apple does not need a subscription product for the free tier. Free is simply the default app behavior when no active paid entitlement exists.

## App Store Connect Setup

1. Complete Agreements, Tax, and Banking.
2. Open App Store Connect.
3. Go to Apps > MealVue > Monetization / In-App Purchases / Subscriptions.
4. Create one subscription group: `MealVue Plans`.
5. Add auto-renewable subscriptions:

```text
mealvue_plus_monthly
mealvue_plus_yearly
mealvue_byo_ai_monthly
mealvue_byo_ai_yearly
mealvue_ai_monthly
mealvue_ai_yearly
mealvue_pro_monthly
mealvue_pro_yearly
```

6. Put all paid products in the same subscription group.
7. Rank subscription levels with Pro above MealVue AI, MealVue AI above BYO AI/Plus, and BYO AI above Free.
8. Add display names, descriptions, pricing, screenshots, and review notes.
9. Attach the subscriptions to an app version/build for review.
10. Test with StoreKit local configuration, sandbox accounts, and TestFlight.

## Code Required

Add a StoreKit 2 subscription layer:

- Import `StoreKit`.
- Define product IDs matching App Store Connect.
- Fetch products with `Product.products(for:)`.
- Present a paywall using `SubscriptionStoreView` or a custom StoreKit 2 purchase UI.
- Purchase with `product.purchase()`.
- Check active access using `Transaction.currentEntitlements`.
- Listen for purchase changes using `Transaction.updates`.
- Maintain an app-level entitlement state such as `free`, `plus`, or `pro`.
- Gate MealVue features based on the active entitlement.
- Add restore purchases.
- Add a Settings row for current plan and manage subscription.

## Suggested Entitlement Model

```swift
enum SubscriptionTier {
    case free
    case plus
    case byoAI
    case mealVueAI
    case pro

    var canUseUnlimitedLogging: Bool {
        self == .plus || self == .byoAI || self == .mealVueAI || self == .pro
    }

    var canUseBYOAI: Bool {
        self == .byoAI || self == .pro
    }

    var canUseBuiltInAI: Bool {
        self == .mealVueAI || self == .pro
    }

    var canUseHealthTrends: Bool {
        self == .plus || self == .byoAI || self == .mealVueAI || self == .pro
    }

    var canUseAdvancedAI: Bool {
        self == .pro
    }
}
```

## MealVue Implementation Stages

1. Create `SubscriptionManager.swift`.
2. Add `SubscriptionTier` and product ID constants.
3. Add a StoreKit configuration file for local testing.
4. Add paywall UI.
5. Add Settings plan status and manage subscription link.
6. Gate Plus and Pro features in the UI.
7. Add free-tier scan/logging limits if desired.
8. Add restore purchases.
9. Configure subscription products in App Store Connect.
10. Test locally, then with TestFlight sandbox/internal testers.

## Production AI Backend Plan

For testing, MealVue can continue using tester-provided OpenRouter keys. For commercial release, the app should not ask normal users to enter AI provider API keys. The production path should use a MealVue-controlled backend.

Recommended architecture:

```text
MealVue iPhone app
→ StoreKit subscription check
→ MealVue backend API on Cloudflare Workers
→ verify user, tier, and usage limits
→ call selected AI provider
→ normalize response into MealVue nutrition JSON
→ return result to app
```

BYO AI users are the exception: they can enter their own provider key and route directly from the app to their chosen provider. This should be treated as a lower-cost power-user tier, not the default consumer experience.

### Why Use Cloudflare Workers

Cloudflare Workers is a good early production backend for MealVue because it avoids running and maintaining a traditional server.

It can handle:

- API key protection.
- Per-user scan limits.
- Subscription-tier enforcement.
- AI usage logging.
- Routing between providers.
- Caching barcode and food lookup results.
- Rate limiting.
- Abuse protection.
- AI Gateway observability.

This is likely more cost-effective than managing a VPS or custom backend infrastructure during the early commercial stage.

### AI Provider Strategy

Do not host GPU models directly at first. Use managed inference providers and route through the backend.

Initial production recommendation:

```text
Phase 1:
Use Cloudflare Workers as MealVue's backend gateway.
Keep external AI providers behind it.

Phase 2:
Add Cloudflare AI Gateway for observability, cost tracking, logs, caching, and routing.

Phase 3:
Evaluate Cloudflare Workers AI vision-capable models as cheaper fallback models or for specific tasks.
```

Providers to benchmark for food photo recognition:

- Gemini Flash direct.
- OpenAI vision models.
- Anthropic vision models.
- OpenRouter routed models.
- Cloudflare Workers AI vision-capable models.

Benchmark criteria:

- Accuracy on real meal photos.
- Average latency.
- Failure rate.
- Cost per scan.
- JSON reliability.
- Nutrition estimate quality.

Accuracy matters more than raw model cost for kidney/heart-health food analysis. Cheap but inaccurate scans can create product and safety problems.

### Subscription-Based AI Limits

Example limit model:

```text
Free:
- Manual logging.
- Basic dashboard.
- No built-in AI, or very small trial limit.

BYO AI:
- Unlimited or high-limit scans because user pays provider.
- Direct provider settings enabled.
- MealVue can still enforce fair-use limits if needed.

MealVue AI:
- 100 AI scans/month.
- Barcode helper.
- Apple Health sync.
- iCloud sync.

Pro:
- 500+ AI scans/month.
- Advanced kidney/heart analysis.
- Health trend correlations.
- Export reports.
```

The app can read StoreKit entitlements locally for UI state, but the backend should enforce usage limits and should not blindly trust the app. For stronger enforcement, the backend should verify subscription status with Apple before granting paid-tier usage.

## Notes

- Use one subscription group for Plus and Pro so Apple can handle upgrades, downgrades, and crossgrades cleanly.
- Avoid locking user-owned health data behind a paywall after it has been created. If a subscription lapses, users should still be able to view/export their existing data.
- Keep medical-risk features conservative. Paid tiers can add convenience and advanced analysis, but the app should continue to clearly state it is not medical advice.
- Keep direct provider API-key settings hidden from normal users. Show them only for BYO AI, developer mode, or internal testing.
- BYO AI should clearly explain that users pay their chosen AI provider separately and MealVue cannot control provider billing, quotas, or model availability.

## Apple Learning Links

Start with these official Apple resources:

- StoreKit overview: https://developer.apple.com/storekit/
- App Store subscriptions overview: https://developer.apple.com/app-store/subscriptions/
- Offer auto-renewable subscriptions in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Auto-renewable subscription fields/reference: https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information/
- Manage pricing for auto-renewable subscriptions: https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/
- Enable billing grace period: https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/
- Subscription analytics in App Store Connect: https://developer.apple.com/help/app-store-connect-analytics/monetization/subscriptions/
- StoreKit `Transaction.currentEntitlements`: https://developer.apple.com/documentation/storekit/transaction/currententitlements
- StoreKit videos: https://developer.apple.com/videos/frameworks/storekit
- Cloudflare Workers pricing: https://developers.cloudflare.com/workers/platform/pricing/
- Cloudflare Workers AI overview: https://developers.cloudflare.com/workers-ai/
- Cloudflare Workers AI pricing: https://developers.cloudflare.com/workers-ai/platform/pricing/
- Cloudflare AI Gateway: https://developers.cloudflare.com/ai-gateway/

Recommended Apple video/search topics:

- StoreKit 2
- `SubscriptionStoreView`
- In-app purchase testing
- App Store Server Notifications
- Subscription offers and win-back offers
- Managing subscription billing and grace periods
