# Localization

Rytivo ships in ten languages. The app follows the iPhone's language unless
someone picks one in Settings > Language, and a choice there applies at once,
without relaunching, and survives relaunch.

## Languages

Chosen on 2026-10-28 by weighing total speakers, share of web content, and the
size of each language's app market.

| Language | Code | Why |
|---|---|---|
| English | `en` | Source language; ~1.5B speakers; about half of all web content; the US is the largest app market. |
| Spanish | `es` | ~560M speakers; second-largest web content language; Latin America and Spain. |
| Chinese (Simplified) | `zh-Hans` | ~1.2B speakers; mainland China is the largest iOS spending market after the US. |
| Hindi | `hi` | ~600M speakers; India is one of the largest download markets. |
| Arabic | `ar` | ~335M speakers across 20+ countries; covers right-to-left layout. |
| French | `fr` | ~310M speakers; top-five web content language; Europe, Canada and Africa. |
| Portuguese (Brazil) | `pt-BR` | ~260M speakers, most of them Brazilian; large download market. `pt-PT` devices also get it. |
| Russian | `ru` | ~255M speakers; top-ten web content language; Cyrillic script. |
| Japanese | `ja` | Third-largest app spending market; fourth web content language. |
| German | `de` | Third web content language; Germany is a top-five app spending market. |

Bengali and Korean were the closest omissions: Bengali for speakers, Korean for
spending. Traditional Chinese devices (`zh-Hant`) are not given Simplified
Chinese; like iOS itself, the app moves on to the next language on the device's
list, and falls back to English.

Sources: Ethnologue 2025 speaker counts, W3Techs content languages
(October 2026), and Sensor Tower's 2025 in-app spending by market.

## How it works

- `Localizable.xcstrings` holds every string the app shows, keyed by its English
  text. `InfoPlist.xcstrings` holds the iOS permission prompts.
- `Services/AppLanguage.swift` decides the language: a choice made in Settings
  wins; otherwise the device's languages are matched the way iOS matches a
  bundle; otherwise English. A choice is also written to `AppleLanguages`, the
  same place iOS keeps Settings > Rytivo > Language, so permission prompts and
  `Locale.current` agree after the next launch. System Default removes it.
- `Services/AppLocalization.swift` holds the current language and switches it
  live. SwiftUI literals (`Text("…")`) follow the `locale` it puts in the
  environment at the root; RTL layout direction is set there too.

## Writing code that shows text

- SwiftUI literals need nothing: `Text("Saved")`, `Button("Retry")`,
  `.navigationTitle("Food")`.
- Anything built as a `String` first uses
  `String(localized: "Saved \(count) workouts", bundle: .app, locale: .app)`.
  `bundle: .app` picks the chosen language rather than the launch language;
  `locale: .app` picks that language's plural rules. A test fails if either is
  missing.
- Dates shown to people use `.locale(.app)`:
  `date.formatted(.dateTime.weekday(.wide).locale(.app))`.
- Never build sentences from translated pieces ("New " + kind): write one string
  per case. Never keep a localized string in a `static let`.
- Leave server and user content (names, posts, food names) as they are.

## Adding or changing strings

1. Build in Xcode; it adds new strings to the catalog. From the command line,
   build with the CI command, then run `bash Scripts/sync-localizations.sh`.
2. Translate each new entry into all nine languages in the catalog editor. Keep
   placeholders, and give counted strings plural forms where the language needs
   them (Russian and Arabic need more than English).
3. Run `bash Scripts/test-account-safety.sh`. `LocalizationCatalogTests` fails
   on any missing translation, stale entry, changed placeholder or wrong plural
   form, and compiles the catalog to check lookups at runtime.

## Known limits

- Legal documents (privacy policy, terms, EULA) stay in English; the app says so
  on those screens. They need professional legal translation, not app copy.
- Text from the server — error messages, the default "Rest" rotation slot
  (worked around on the client), For You topic names — arrives in English.
- Permission prompts and other iOS-drawn text switch at the next launch, not
  live. Reminders already scheduled are rewritten when the language changes;
  notifications already delivered are not.
- Debug launch flags: `REPBASE_LANGUAGE_PREVIEW=1` opens the Language screen;
  with `REPBASE_LANGUAGE_SWITCH=<code|system>` it picks a language after a few
  seconds, to watch a live switch from a script.
