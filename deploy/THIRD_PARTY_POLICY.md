# Third-party dependency policy

The MVP accepts the permissive MIT, ISC, BSD, Apache-2.0, 0BSD, BlueOak, CC0, CC-BY, MPL-2.0, Python-2.0, and PostgreSQL license families represented in the committed lockfiles.

CI rejects packages with missing or newly introduced license expressions until this file and the explicit allowlists are reviewed. It also fails on RAG/pgvector dependencies and unapproved exercise media. Automated CVE scanning of dependencies and container images is intentionally not a release gate for this private MVP; dependency versions remain locked and updates are reviewed separately.

Uploaded meal images are identified, dimension-checked and re-encoded by `SkiaSharp` 4.153.1, under MIT. The API executable references `SkiaSharp.NativeAssets.Linux.NoDependencies` 4.153.1, also under MIT, for its Linux container; it bundles the required native Skia runtime and its third-party notices. Both packages are version-pinned and checked by the NuGet license policy. Raw, DNG and other unaccepted formats remain rejected; the accepted JPEG, PNG and WebP inputs are decoded to pixels and emitted as metadata-free JPEGs.

## Open Food Facts data

Barcode lookup and explicit product search use the Open Food Facts database as a read-only external source. Database contents are available under the Open Database License (ODbL); individual database contents are covered by the Database Contents License. The UI attributes Open Food Facts at the point of use, labels stale or incomplete community data, and does not retrieve or redistribute product images.

The application stores only the user-confirmed product name, optional brand, barcode/provider provenance, retrieval time and a nutrient snapshot needed for that user's diary. Search queries, provider response bodies and barcodes are excluded from application logs and telemetry labels. Operators must keep the Open Food Facts contact address current and review the provider terms before materially expanding caching, redistribution or public availability.

## OpenAI meal estimation

Meal estimation is an explicit, online-only action. The selected text and at most one server-sanitized image are sent to the OpenAI Responses API with `store=false`, `background=false` and a bounded structured-output schema. The only tool is OpenAI's `web_search`, restricted to the nutrition sites configured in `MealEstimation:WebSearchDomains` (by default fddb.info, naehrwertrechner.de, openfoodfacts.org and fdc.nal.usda.gov) to look up reference values; the search queries are formed by OpenAI from the meal description. It can be switched off with `MealEstimation:WebSearchEnabled=false`, and the server keeps a returned source link only if it is an https page on one of these sites. Gainer does not persist the source image, prompt, provider response or editable draft in PostgreSQL, Blob Storage, on-device storage, application logs, traces or metric labels. Only components reviewed and confirmed by the user become ordinary nutrition-entry snapshots marked with technical AI provenance.

`store=false` disables Responses application-state storage but is not a promise of zero provider retention. Under OpenAI's default API data controls, request and response content may occur in abuse-monitoring logs retained for up to 30 days; approved Zero Data Retention or Modified Abuse Monitoring controls can alter this. The in-app consent text must state this distinction, identify OpenAI as recipient, describe the estimate as non-authoritative and remain aligned with the data controls configured for the production OpenAI project.

## Strava export

Users can connect their own Strava account. The API stores the access and refresh tokens encrypted with ASP.NET Core Data Protection and never sends them to the app. Only records of the kinds the user switched on, or a single record the user explicitly sends, leave Gainer: cardio sessions as TCX files (start, end, heart-rate series, distance, energy, template name, notes, target zone, average power) and, if enabled, strength workouts (title, duration, notes, exercise names with sets, weights and repetitions). Gainer requests only `read,activity:write`, reads no Strava activities and stores only the Strava athlete id and name, upload and activity ids. Disconnecting revokes the tokens at Strava and deletes them; activities already in Strava stay there and are governed by Strava's terms.
