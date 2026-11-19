# Cookbooks integration testing

Feature branch: `work/testflight-fixes-2026-10-27`.
Backend: `P-B-LLC/repbase`, `work/testflight-calendar-sync-2026-10-28`, migrations 0087/0088.
No production deployment or main promotion is part of this change.

Editable design: https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=161-2949
Clickable prototype: https://www.figma.com/proto/FbMNgG8cuZfrRFzQTtIVCy?node-id=161-3115

## Implemented flow

Food > Cookbooks lists folder summaries. Create or rename a named cookbook,
open it, and add/edit recipes. Every recipe must have a selected cookbook.
Social meal saves open the same destination picker; full folders show their
capacity and are disabled. Create another cookbook directly from the picker.
Move recipes with the recipe editor's Cookbook field or the row context menu.
An empty cookbook can be deleted through the visible options menu. Recipe names
are scoped to their cookbook, so different cookbooks may keep the same name.

Post cookbook previews the whole collection and asks for caption/audience.
The server freezes all recipes, with ingredients, nutrition and method, into
one bounded publication snapshot. Community cards show the summary; View all
recipes loads the full cookbook lazily. Save cookbook creates one private,
editable collection, and retrying returns the existing copy.

The overview loads no ingredients. Selected-folder reads are capped at 20
recipes; repeated navigation uses a short cache. Pull to refresh and foreground
refresh fetch server truth. Save callbacks refresh the active library. Only
the explicit meal planner loads the complete recipe library. A refresh cannot
overwrite a later save or a newer refresh; old-account responses are discarded.

## Checks and simulator review

The API client was regenerated on macOS, not manually edited. The native CI
checks Debug, Release, generated-client parity, catalog coverage and regression
tests. CookbookSyncTests exercise stale and deliberately reordered responses.
Backend Cookbook integration runs 59 affected tests on PostgreSQL 17, including
concurrent saves into the twentieth slot and migration of 43 legacy recipes.

For real synchronization testing, use an HTTPS TESTING backend with migration
0087 and the matching branch installed. The production address has not been
changed or deployed by this task. Old clients omit the now-required cookbook
destination; coordinate any future beta backend/app rollout.

After pulling the testing branch on a Mac, build against that testing origin:

```bash
export REPBASE_API_URL="https://YOUR-TESTING-API-ORIGIN"
INSTALL_SIMULATOR=1 bash Scripts/validate-food-refresh.sh
```

For illustrative visual fixtures only, after a Debug simulator build:

```bash
bash Scripts/capture-cookbooks-preview.sh .build/food-validation/Build/Products/Debug-iphonesimulator/Rytivo.app
```

CI also captures light/dark library, contents, picker, creation and posting
screens after related changes. These previews do not prove live connectivity.
Manually test create/rename, save a Social recipe, move a recipe, the 20/21 limit,
post/open/save a complete cookbook, refresh from a second client, account switch,
large text, VoiceOver and both appearance modes against the testing backend.
