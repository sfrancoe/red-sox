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

Commercial builds fail while prototype MLB endpoints remain in the native runtime.
The Players directory itself uses CC0 Wikidata facts, a CC BY-SA roster and team
history, ODC-licensed Chadwick identity mappings, and Retrosheet career statistics.
Required attribution is displayed in the app, and no player photography is included.

## Human decisions before the first TestFlight

- Final 1024×1024 app icon
- iPhone-only launch or fully tested iPad support
- Privacy policy and support URLs
- Independent product name and visual identity, or written MLB trademark authorization
- Attribution and source-link review for Wikimedia, Chadwick, and Retrosheet player data
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
