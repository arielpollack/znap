# Znap

## Workflow

- After completing each request, run `make run` to build and launch the app.

## Spec-Driven Development

Every change to Znap MUST keep specs in sync. This is non-negotiable.

### Before writing code:
1. Read `docs/specs/PRODUCT.md` to understand existing features and architecture.
2. Read `docs/specs/ROADMAP.md` to understand priorities and status.
3. If implementing a new feature, update the ROADMAP status to "In progress".

### After completing a feature or change:
1. **Update `docs/specs/PRODUCT.md`:**
   - Add new features to the relevant feature table with status "Done".
   - Update architecture sections if new files/services were added.
   - Update preferences table if new settings were added.
2. **Update `docs/specs/ROADMAP.md`:**
   - Mark completed features as "Done" with the version number.
   - Add to version history.
3. **Update `docs/app-store/LISTING.md`:**
   - Add the feature to the app description if user-facing.
   - Update "What's New" section.
   - Flag if a new screenshot is needed (ask user to capture).
4. **Update `docs/app-store/ASO.md`:**
   - Add relevant keywords if applicable.
   - Check the ASO checklist.

### Spec files (source of truth):
- `docs/specs/PRODUCT.md` — Full product spec: features, architecture, preferences, models.
- `docs/specs/ROADMAP.md` — Competitive analysis, prioritized roadmap, version history.
- `docs/app-store/LISTING.md` — App Store listing: name, description, keywords, screenshots, privacy.
- `docs/app-store/ASO.md` — ASO strategy, keyword research, ranking targets.

### Rules:
- NEVER add a feature without updating specs.
- NEVER remove a feature without updating specs.
- NEVER change a shortcut, setting, or behavior without updating specs.
- If a spec file doesn't describe something that exists in code, add it.
- When in doubt about how something works, READ THE SPEC FIRST, then verify in code.
