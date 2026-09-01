# App Store readiness

Run the native app's preflight checker from the repository root:

```bash
python3 scripts/app_store_preflight.py
```

Before TestFlight, also verify the live non-metered data feeds:

```bash
python3 scripts/app_store_preflight.py --network
```

The checker deliberately skips the metered X discovery endpoint so an audit cannot
create an unexpected API charge. A green automated report does not guarantee App
Review approval; trademark, third-party content, privacy disclosures, screenshots,
review notes, and the signed archive still require a human review.

## Human decisions before the first TestFlight

- Final 1024×1024 app icon
- iPhone-only launch or fully tested iPad support
- Privacy policy and support URLs
- Red Sox trademark/affiliation presentation
- Permission and attribution for newspaper and X content
- App Store name, subtitle, description, category, age rating, and screenshots
- Review notes explaining the app's native utility and live-data sources

When those decisions are made, add `metadata.json` in this folder:

```json
{
  "privacy_policy_url": "TODO",
  "support_url": "TODO",
  "review_notes": "TODO"
}
```
