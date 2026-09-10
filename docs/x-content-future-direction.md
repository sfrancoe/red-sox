# Hub Ball X content — idea to revisit

**Recorded:** September 8, 2026  
**Status:** Deferred product idea. The user likes this direction and asked to save it for a future discussion; implementation is not authorized by this note.

## Preferred experience

Combine a small selection of complete, official X post embeds inside Hub Ball with a way to browse the broader conversation on X.

- Keep Hub Ball's team branding, navigation, and optional editorial context around the posts.
- Render selected posts through X's official widgets in a `WKWebView`, rather than reconstructing post cards from extracted content.
- Offer a “Browse the team's X list” entry that could open the actual X website in `SFSafariViewController`; Done returns the user to Hub Ball.
- Respect X's mobile deep-link requirements for post links, including opening the X app when installed where required.
- If an embed cannot load, show a clear link to the source instead of stale copied post content.

The user liked both the official-embed concept and the in-app browser, and endorsed exploring their combination. This is a preference, not a finding that X permits the architecture.

## Questions to resolve when revisiting

1. Obtain clarification of X's permission for official widgets in a commercial iOS `WKWebView`. The policies reviewed on September 8 encouraged official embeds, but the Developer Agreement also contained a broad iframe/similar-embedding prohibition. Confirm the applicable use case and access tier; do not treat payment for the API as blanket permission.
2. Separate discovery from display. Selected post IDs could come from editorial selection or an approved API workflow. Automated relevance filtering and Most Liked ranking may still require paid API retrieval. An embedded or browser-based list would use X's presentation and would not preserve Hub Ball's custom filtering/ranking automatically.
3. Replace the current list-HTML extraction path if adopting this direction. `netlify/functions/x-posts.mjs` extracts `__NEXT_DATA__` from syndication HTML; `x-discovery.mjs` separately uses the authenticated API. Include the static generated-feed fallback in any migration review.
4. Test actual iPhone/iPad behavior: widget reliability, media, scrolling, load performance, unavailable/deleted posts, navigation, and logged-in versus logged-out browsing. Do not assume Safari or X login sessions carry into the in-app browser.
5. Address applicable privacy/consent, content updates/removals, and App Store authorization requirements. Official rendering does not settle permission for the overall service.
6. Reconcile the official external widget script with the repository's existing no-CDN-script rule and CSP before implementation; a future exception needs to be scoped explicitly.

## Design references

Concepts use fictional posts and approximate X's presentation, not verified live widget screenshots:

- [Interactive comparison](../output/visualizations/hub-ball-comparison.html)
- [Embed and browser image](../output/visualizations/embed-and-browser.png)
- [Native and editorial comparison image](../output/visualizations/native-and-editorial.png)

## Policy and technical references

Recheck these when work resumes; the September 8 review is not permanent guidance.

- [X Developer Agreement](https://docs.x.com/developer-terms/agreement)
- [X Developer Policy](https://docs.x.com/developer-terms/policy)
- [X display requirements](https://docs.x.com/developer-terms/display-requirements)
- [Official embedded posts](https://docs.x.com/x-for-websites/embedded-posts/overview)
- [X oEmbed API](https://docs.x.com/x-for-websites/oembed-api)
- [Apple SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller)

No reminder date was requested. No implementation, deployment, or outreach to X was performed as part of saving this note.
