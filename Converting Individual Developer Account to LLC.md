# Converting an Individual Apple Developer Account to an LLC

You can continue using the current individual Apple Developer membership during TestFlight. The cleanest path is to convert the existing membership from **Individual** to **Organization** after forming the LLC, rather than creating a second developer account and transferring Hub Ball.

An individual account displays the account holder's personal legal name as the App Store seller. An organization account displays the LLC's legal entity name. Apple supports converting an individual membership when the account holder is a founder or cofounder of the organization.

Apple guidance: [Updating your account information](https://developer.apple.com/help/account/membership/updating-your-account-information)

## What to do now

Continue with:

- App Store metadata
- Screenshots
- Builds and TestFlight
- Internal and external beta testing

Stop before submitting Hub Ball for public App Review. Complete the LLC formation and Apple membership conversion first.

These items can also wait until the LLC exists:

- Paid Apps Agreement
- Tax forms
- Banking information
- Final EU trader verification
- Public App Store submission

## Once the LLC is formed

1. Obtain the LLC's EIN.
2. Establish a business address and phone number.
3. Set up a domain and business email address, such as `you@yourcompany.com`.
4. Have a functional public website associated with that domain.
5. Look up or request the LLC's free D-U-N-S Number through Apple and Dun & Bradstreet.
6. Ensure the D-U-N-S record exactly matches the LLC's:
   - Legal name
   - Legal address
   - Entity type
7. Allow up to five business days for D&B to issue the number and up to two additional business days for Apple to receive it.

Apple guidance: [D-U-N-S Number](https://developer.apple.com/help/account/membership/D-U-N-S/)

## Request the Apple membership conversion

Sign in at the [Apple Developer account portal](https://developer.apple.com/account/), then:

1. Open **Membership details**.
2. Click **Update your information**.
3. Select the request to update an individual membership to an organization.
4. Provide the LLC's legal name, D-U-N-S Number, website, business email, and requested formation documents.
5. State that you are the founder and have legal authority to bind the LLC.
6. Ask Apple to confirm the public **seller/developer name** that will appear after conversion.

Apple accepts LLCs as legal entities but does not accept a DBA or trade name by itself for organization enrollment. The LLC's legal entity name becomes the seller name.

Apple guidance: [Program enrollment requirements](https://developer.apple.com/help/account/membership/program-enrollment/)

## Do not create a separate organization account by default

Do not create a separate organization Developer Program account unless Apple instructs you to do so. A conventional app transfer is unsuitable before launch because Apple requires an app to have at least one publicly released App Store version before it can be transferred. An unreleased TestFlight app does not meet that requirement.

Apple guidance: [App transfer criteria](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria)

Converting the existing membership in place should preserve the current team, Hub Ball record, bundle ID, TestFlight setup, and other app records. The Boston and Yankees app records would become part of the converted organization account as well.

## Public-launch checkpoint

Hub Ball's public App Review submission should remain blocked until these are complete:

- LLC formation
- D-U-N-S verification
- Individual-to-organization Apple Developer membership conversion
- Confirmation of the public seller name
- LLC tax and banking setup, as applicable
- EU trader details, as applicable

This is operational guidance based on Apple's published requirements, not legal or tax advice.
