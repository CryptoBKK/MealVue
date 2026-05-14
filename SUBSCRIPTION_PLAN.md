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

### Pro

- Everything in Plus.
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
mealvue_pro_monthly
mealvue_pro_yearly
```

6. Put all paid products in the same subscription group.
7. Rank subscription levels with Pro above Plus.
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
    case pro

    var canUseUnlimitedLogging: Bool {
        self == .plus || self == .pro
    }

    var canUseHealthTrends: Bool {
        self == .plus || self == .pro
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

## Notes

- Use one subscription group for Plus and Pro so Apple can handle upgrades, downgrades, and crossgrades cleanly.
- Avoid locking user-owned health data behind a paywall after it has been created. If a subscription lapses, users should still be able to view/export their existing data.
- Keep medical-risk features conservative. Paid tiers can add convenience and advanced analysis, but the app should continue to clearly state it is not medical advice.

