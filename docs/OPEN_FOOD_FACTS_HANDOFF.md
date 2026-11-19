# Food search and barcode testing candidate — 2026-10-29

Branch: `work/testflight-fixes-2026-10-27`, draft PR #39.
Backend counterpart: repbase `work/testflight-calendar-sync-2026-10-28`, PR #36.
Neither main nor the live backend/TestFlight is changed by this candidate.

- Submit food/brand searches explicitly; no upstream search on each keystroke.
- Scan packet barcodes on a supported iPhone or type a barcode on any device.
  Camera permission is requested only when opening the scanner. Frames remain
  on device; only the product number goes through the authenticated backend.
- Review the portion before adding. Measured 100g/100ml results accept grams/
  millilitres and use the existing decimal, retry-safe food save path.
- Recents/manual entry remain available for missing or incomplete products.
  Existing meals are not deleted or reinterpreted. OFF attribution is visible.
- New strings cover all ten app languages; privacy text names the new provider.

## Mac validation still required

The API wire shape is unchanged, but its descriptions changed. Generated Swift
must be regenerated on macOS, never hand-edited. Windows cannot validate Xcode
or the real camera. After preserving any local changes, run from this branch:

```bash
git pull --ff-only
bash Scripts/generate-api-client.sh
bash Scripts/test-account-safety.sh
INSTALL_SIMULATOR=1 bash Scripts/validate-food-refresh.sh
git diff -- API/GeneratedSources
```

Set `REPBASE_API_URL` to the existing configured HTTPS origin first. A backend
running the counterpart candidate is required for end-to-end OFF results;
rebuilding iOS does not deploy it. Commit and push regenerated sources on this
testing branch after inspection. CI's generated-client gate remains enabled.

Before promotion: test search, empty/offline/retry, valid/invalid manual codes,
EAN/UPC scanning on an iPhone, camera denial, cancellation, repeated scans,
100g/100ml and labelled-serving portions, decimal separators, meal totals,
save retry and account switching. Check light/dark, large text and VoiceOver.
No photo-based food estimation is included in this change.
