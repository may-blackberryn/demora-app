# Draft: "Location (optional)" for the website privacy policy

Status: **draft for the owner** (2026-11-12, When & where step 6). Not added to
`demora-website` and not deployed: that is a separate repository and the
owner's deploy (spec Q5: the section ships with the release that contains
When & where). The wording below matches what the iPhone build does as of
the When & where steps 1–6 on branch `design/full-redesign`; recheck it
against the release build before publishing.

## Where it goes

In `demora-website/privacy-policy.html`, as its own `<h2>` section after the
"Time check" paragraph and before "What we don't do". Keep the existing
sentence in "What we don't do" ("We do not collect analytics, advertising
identifiers, or location data.") unchanged: it stays true, because nothing
about your location reaches us.

## Proposed text (HTML)

```html
<h2>Location (optional)</h2>
<p>Demora uses your location only if you create a When &amp; where rule with
a place or a country, and only while you use the app. It asks iOS for your
location once when you tap <strong>Check in</strong>, <strong>Set to where I
am now</strong> or <strong>Use the country I'm in</strong>. It never uses
your location in the background and never asks for "Always" access.</p>

<p>The location is checked on your iPhone and then discarded: Demora doesn't
store it, log it or send it to us or anyone else. Countries are worked out on
your iPhone from map data built into the app (Natural Earth, public domain),
with no network request. Only the result of a check (for example "at Home:
yes") is used to start free time or a block.</p>

<p>A saved place keeps only its name, its centre and its size, on your
device (and in your device backup, like other app data). A country is saved
as its two-letter code. If a trusted contact approves a change to a rule,
the request they see includes the place's or country's name, never its
coordinates or size.</p>

<p>You can turn location off for Demora at any time in iOS Settings; rules
that need a place or country then can't be checked in, and everything else
keeps working.</p>
```

## Plain-text version (for review)

- **When:** only for When & where rules with a place or country; only while
  you use the app; one reading per tap on Check in, Set to where I am now or
  Use the country I'm in. No background location, no "Always".
- **Where it goes:** nowhere. Checked on the iPhone, then discarded; not
  stored, logged or sent. Countries come from map data inside the app; no
  network request.
- **What is saved:** a place's name, centre and size; a country's code. On
  the device and in its backup.
- **Trusted contacts:** an approval request shows place or country names,
  never coordinates or sizes.
- **Turning it off:** iOS Settings → Demora → Location.

## Notes for the owner

- Accurate as built: `Latch/LocationCheck.swift` is the only CoreLocation
  code (While Using, `requestLocation()` once per tap, 15 s timeout,
  stopped on resolve or cancel); `Latch/CountryLookup.swift` is pure
  arithmetic on the bundled `CountryBorders.bin`; no map, geocoder or
  address search ships (the spec's optional "Show on map" was deferred in
  step 4). **If a map ever ships**, add: "If you open a map, Apple Maps loads
  the area shown."
- Block check-ins (step 6) count a place or country the reading can't rule
  out (near a border, approximate location): this changes when a block
  starts, not what is read or kept, so the policy text doesn't change.
- App Store privacy label and `Latch/PrivacyInfo.xcprivacy`: no change
  expected (nothing leaves the device, so location isn't "collected").
  Confirm against Apple's current definitions before submitting.
- The App Review notes should say how to test with a place near the
  reviewer (they won't be in Mexico) and that location is requested only on
  Check in.
