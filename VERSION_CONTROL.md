# MealVue Version Control

MealVue uses Git with the GitHub remote:

```bash
origin https://github.com/CryptoBKK/MealVue.git
```

## Daily Workflow

1. Check changes:

```bash
git status --short
```

2. Review what changed:

```bash
git diff
```

3. Create a checkpoint commit after a working build:

```bash
git add .
git commit -m "Describe the completed work"
git push origin main
```

## TestFlight Workflow

Before uploading a TestFlight build:

```bash
git status --short
git log --oneline -1
```

Use the latest commit hash in release notes or your testing notes so each TestFlight build maps back to a known code state.

## Suggested Commit Points

- After a successful Xcode build.
- Before uploading to TestFlight.
- After a tester-reported bug is fixed and verified.
- Before large feature work such as HealthKit/iCloud changes.

## Branches

Use `main` for stable builds. For larger features, create a branch:

```bash
git switch -c feature/short-feature-name
```

Merge back to `main` only after the branch builds and the feature has been tested.

