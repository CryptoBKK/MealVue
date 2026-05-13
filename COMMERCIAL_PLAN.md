# MealVue Commercial Upgrade Plan

**Forked from:** Kidney Foods (May 2026)  
**Goal:** Transform into a commercial-grade kidney health meal tracking app for Thai/SE Asia market  

---

## Phase 1: Foundation (Can Test in Simulator, Free Account)

### 1.1 Project Setup
- [x] Fork Kidney Foods → MealVue
- [ ] Update bundle ID: `Inphase.Kidney-Foods` → `com.mealvue.app`
- [ ] Update app display name: "Kidney Foods" → "MealVue"
- [ ] Create new App Store Connect app (when paid account ready)
- [ ] Add app icon variations (Thai language support)

### 1.2 Sample Data System (Test Without Real Patients)
- [ ] Create `SampleData.swift` with:
  - 3 Thai patient profiles (CKD Stage 3, 4, 5 on dialysis)
  - 30 days of meal logs with Thai foods (Som Tam, Tom Yum, Pad Thai, etc.)
  - Mock lab results (eGFR, creatinine, potassium, phosphorus)
- [ ] Add "Load Demo Data" button in Settings
- [ ] Pre-populate simulator Photos app with Thai food images for camera testing

### 1.3 Simulator-Friendly Camera Testing
- [ ] Add `#if targetEnvironment(simulator)` mock camera toggle
- [ ] Bundle 5-10 sample Thai food images in Assets.xcassets
- [ ] Update LogFoodView to use PHPicker (works in simulator) instead of camera-only flow
- [ ] Add drag-and-drop image support (drag image to simulator = instant test)

---

## Phase 2: Core Commercial Features (Local-First, No Paid Account Needed)

### 2.1 HealthKit Integration (Works in Thailand ✅)
- [ ] Add HealthKit capability in Xcode
- [ ] Request permissions: Kidney-related lab results, dietary water intake
- [ ] Read mock data in simulator: eGFR, creatinine, potassium levels
- [ ] Write logged nutrients back to Health app
- [ ] Add "Health Trends" tab: correlate diet changes with lab improvements
- [x] Add SwiftData + CloudKit private database sync for meal data backup and same-account device sync
- [ ] Enable iCloud/CloudKit in Apple Developer portal for `iCloud.com.mealvue.app` after developer approval
- [ ] Validate iCloud sync on two real devices signed with the approved developer team

### 2.2 Improved Dashboard UI (Commercial-Grade Design)
- [ ] Replace basic list with card-based design
- [ ] Add circular progress rings (like Apple Activity app):
  - Sodium ring (target: 2000mg)
  - Potassium ring (target: 3000mg)
  - Phosphorus ring (target: 1000mg)
  - Protein ring (target: varies by CKD stage)
- [ ] Color-coded warnings: Green (safe) < 80%, Yellow (caution) 80-100%, Red (exceeded) > 100%
- [ ] Add today's sparkline charts (mini bar charts for each nutrient)

### 2.3 Barcode Scanner (Local Database, No Subscription Needed Initially)
- [ ] Add `AVFoundation` barcode scanning
- [ ] Create local JSON database of common Thai packaged foods:
  - 100+ items from Tesco Lotus, Big C, 7-Eleven
  - Pre-calculated kidney-relevant nutrients
- [ ] Add "Scan & Compare" feature: scan 3 similar products, see which is kidney-friendliest

---

## Phase 3: Revenue Features (Add When Ready to Monetize)

### 3.1 Freemium Model (StoreKit 2)
- **Free Tier:**
  - Manual meal logging
  - 3 AI analyses/day
  - Basic nutrient tracking
  - Sample data access

- **Premium Tier ($4.99/mo or $39.99/yr):**
  - Unlimited AI analyses
  - HealthKit integration
  - Barcode scanner + full database
  - PDF reports for doctors
  - Custom meal plans

- **Professional Tier ($99/yr - B2B):**
  - Multi-patient dashboard (for nephrologists)
  - Clinic branding option
  - Bulk patient data export

### 3.2 AI Enhancements
- [ ] Add Thai language support for AI prompts
- [ ] Localize AI responses: "High sodium" → "โซเดียมสูง" (optional toggle)
- [ ] Add confidence scoring: "90% sure this is Som Tam"

### 3.3 Meal Planning (Premium Feature)
- [ ] Create Thai kidney-friendly recipe database (50+ recipes)
- [ ] Weekly meal planner with auto-calculated nutrients
- [ ] Shopping list generator
- [ ] Integration with Thai grocery delivery (if available)

---

## Phase 4: Testing Strategy (All in Simulator, Free Account)

### 4.1 Sample Patient Testing
Load these profiles to verify all features:

**Patient A: Somchai (CKD Stage 3a, Early)**
- Age 58, Male, 72kg, 168cm
- Targets: Protein 80g, Sodium 2000mg, Potassium 3000mg, Phosphorus 1000mg
- Test: Log 3 days of Thai meals, verify warnings trigger correctly

**Patient B: Malee (CKD Stage 4, Pre-dialysis)**
- Age 64, Female, 58kg, 156cm
- Targets: Protein 58g, Sodium 1500mg, Potassium 2000mg, Phosphorus 800mg
- Test: Strict diet, verify red warnings appear at 80% threshold

**Patient C: Prasert (CKD Stage 5, On Dialysis)**
- Age 71, Male, 68kg, 170cm
- Targets: Protein 85g, Sodium 2000mg, Potassium 2000mg, Phosphorus 1000mg
- Test: High-protein dialysis diet, track phosphorus binders

### 4.2 Camera Testing Without Real Camera
1. Drag 10 Thai food photos to simulator
2. Test AI analysis with each (requires API key)
3. Verify image saves to SwiftData correctly
4. Test "Retake Photo" and "Manual Review" flows

### 4.3 HealthKit Mock Data
In simulator Health app:
- Add mock eGFR readings: 52, 48, 45 (declining trend)
- Add potassium labs: 4.2, 4.8, 5.1 (rising concern)
- Verify MealVue shows correlation: "Your potassium rose 21% as you ate more processed foods"

---

## Phase 5: Pre-Launch (Requires Paid $99 Account)

### 5.1 App Store Assets
- [ ] Create app preview videos (use simulator screen recordings)
- [ ] Design App Store screenshots with Thai patient testimonials
- [ ] Write privacy policy (mention HealthKit data handling)
- [ ] Add FDA disclaimer: "Not medical advice, consult your nephrologist"

### 5.2 TestFlight Beta
- [ ] Invite 10-20 Thai kidney patients for beta testing
- [ ] Collect feedback on Thai food database accuracy
- [ ] Test on real devices (iPhone + iPad)

### 5.3 Localization
- [ ] English (primary)
- [ ] Thai (ถิ่น) - critical for local market
- [ ] Consider: Chinese (for medical tourism in Bangkok)

---

## Immediate Next Steps (This Week)

1. **Commit the forked MealVue project** (save current state)
2. **Create SampleData.swift** (I can write this now with 30 days of Thai meals)
3. **Update LogFoodView** to use PHPicker (camera optional, works in simulator)
4. **Add "Load Demo Data" button** to SettingsView
5. **Test with Somchai profile** (CKD Stage 3, verify all warnings work)

---

## Technical Debt to Address Before Launch

- [ ] Add unit tests (critical for health app reliability)
- [ ] Improve error handling (AI calls fail silently sometimes)
- [ ] Add data export feature (users need to leave with their data)
- [ ] Create onboarding flow (3-screen wizard for new users)
- [ ] Add "Made for kidney warriors" branding (Thai context)

---

## Revenue Timeline Estimate

| Month | Feature Added | Est. Revenue (if 1000 users) |
|-------|----------------|--------------------------------|
| 1-2   | Launch free version, collect users | $0 (growth phase) |
| 3      | Add premium tier, Thai localization | $500/mo (10% convert) |
| 6      | HealthKit + Barcode scanner | $2000/mo (20% convert) |
| 12     | B2B professional tier | $5000/mo + contracts |

---

**Next Action:** Want me to create the `SampleData.swift` file with 30 days of Thai meal logs + 3 patient profiles you can load instantly?
