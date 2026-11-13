# Custom Product Pages (issue #33)

One App Store Custom Product Page per audience, each with its own screenshots,
preview video, promotional text, deep link and analytics. This kit covers the
first two pages: **Black Holes** and **Three-Body Problem**. Relativity,
Habitable Zones, Sgr A\* and Tools come later, guided by the analytics.

Everything here can be regenerated on any machine:

- `AppStore/capture-screenshots.sh` builds the Debug app and captures every
  screenshot on the iPhone 6.3" and iPad 13" simulators.
- The scenes live in `CosmicPathSwift/Views/ScreenshotScene.swift` (Debug only).
  Each scene is a deep-link scenario (`Models/AppScenario.swift`) plus
  screenshot-only tweaks, and it freezes itself at a fixed capture moment, so
  captures are repeatable.
- Output goes to `AppStore/screenshots/<device>/<page>/NN-<scene>.png`
  (git-ignored).

All character counts below were measured with a script, not by hand.

---

## Capturing

```bash
AppStore/capture-screenshots.sh                  # both pages, iPhone + iPad
AppStore/capture-screenshots.sh black-holes      # one page
SKIP_BUILD=1 AppStore/capture-screenshots.sh     # reuse the last build
AppStore/capture-screenshots.sh --video planetDisruption 25        # iPhone clip
AppStore/capture-screenshots.sh --video figureEight 20 ipad        # iPad clip
DEVICES=iphone AppStore/capture-screenshots.sh                     # iPhone only
```

| Device | Simulator | Size (px) | Override |
|---|---|---|---|
| iPhone 6.3" | iPhone 17 | 1206 × 2622 | `IPHONE_UDID` |
| iPad 13" | iPad Pro 13-inch (M5) | 2064 × 2752 | `IPAD_UDID` |

The iPhone size follows the app's listing: App Store Connect asks custom product
pages for the 6.1"/6.3" slot, which takes **1179 × 2556 or 1206 × 2622** (portrait;
the landscape versions are accepted too). A 6.9" capture (1320 × 2868) is rejected
there.

**One-time iPad setup:** in the iPad simulator, set Settings → Multitasking &
Gestures → **Full Screen Apps**. In windowed mode, iPadOS draws a resize grabber
in the bottom-right corner of every capture.

The status bar is set to 9:41, full signal and a full battery. The Debug app takes
up to ~8 s to show its first frame on a cold simulator. `LAUNCH_SECONDS`
(default 12) covers that, and the scene's own timing starts once the canvas
is on screen.

**Capture moments** (`ScreenshotScene.captureMoment`). Three kinds: after N s
of running, at a simulated time (repeatable, because the number of steps per frame
is fixed), or N s after the orbit-ending event's banner appears.

| Scene | Freezes | Shows |
|---|---|---|
| `planetDisruption` | 20 s of running | the planet stretched into a debris stream |
| `probeRosette` | 6 s | the precessing rosette building up |
| `horizonPlunge` | 5.5 s at 1 s = 100 µs | the probe spiralling in, just outside the horizon (it crosses at ≈ 5.9 s) |
| `blackHoleVisual` | 4 s | stable orbit at 3.6 rₛ: horizon, photon sphere, ISCO, disk, habitable zone |
| `s2` | 2.5 s at 1 s = 10 years | S2's full ellipse |
| `figureEight` | t = 130 | one full loop of the figure-8 |
| `threeBodyChaos` | t = 30,000 | B flung out; the twin's dashed trails have split off |
| `pythagoreanEjection` | 0.3 s after the ejection | "Ejection" banner, B's trail leaving the frame |
| `lagrangeBreakup` | t = 510 | the triangle broken into loops (intact until ≈ 470) |

**Preview videos:** App Store previews are 15–30 s. `--video` records a raw
`.mov` with the scene running (not frozen). Trim the launch screen off the
start and cut to the storyboard below in any editor (iMovie or Final Cut). Apple
requires previews to be captured from the app itself, which these clips are.
Export them at the slot's preview resolution: iPhone 6.1"/6.3" **886 × 1920**
(App Store Connect), iPad 13" 1200 × 1600.

**Framing (optional):** the raw captures can be uploaded as they are. For framed
shots with captions, lay them out in Claude Design with the captions below and
export PNGs at the same pixel sizes (Claude Design can't publish to App Store
Connect; upload by hand).

---

## Page 1 — Black Holes

- **Reference name** (App Store Connect, internal): `Black Holes`
- **Audience:** space enthusiasts searching for black holes.
- **Deep link:** `cosmicpath://scenario/black-hole/planet` (active from the
  version with deep links, see "App update" below)

**Promotional text** (164 / 170):

> Watch a black hole tear a planet apart, orbit a few Schwarzschild radii from the horizon and follow star S2 around Sagittarius A*. General relativity, running live.

**Keywords to assign** (from the app's keyword field): `black hole`,
`event horizon`, `relativity`, `einstein`, `space`.

**Screenshots** (the first two show in search results, so they answer the search):

| # | Scene | Caption |
|---|---|---|
| 1 | `planetDisruption` | Watch a black hole tear a planet apart |
| 2 | `probeRosette` | Orbit a few Schwarzschild radii from the horizon |
| 3 | `horizonPlunge` | Cross the event horizon |
| 4 | `blackHoleVisual` | Horizon, photon sphere and ISCO |
| 5 | `s2` | Follow star S2 around Sagittarius A* |

**Preview storyboard** (~25 s):

| Time | Clip (`--video` scene) | On screen |
|---|---|---|
| 0–8 s | `planetDisruption` | the planet stretches into a debris stream |
| 8–15 s | `probeRosette` | the rosette builds turn by turn |
| 15–20 s | `horizonPlunge` | the probe spirals in; "Event Horizon Crossed" |
| 20–25 s | `s2` | S2 traces its ellipse around Sgr A* |

---

## Page 2 — Three-Body Problem

- **Reference name:** `Three-Body Problem`
- **Audience:** fans of the book and TV series, and chaos enthusiasts.
- **Deep link:** `cosmicpath://scenario/three-body/figure-8`

**Promotional text** (167 / 170):

> The three-body problem, live: watch the famous figure-8, then nudge three stars by one part in a million and see the copies diverge until one star is flung into space.

**Keywords to assign:** `three body`, `chaos`, `gravity`, `physics`.

**Screenshots:**

| # | Scene | Caption |
|---|---|---|
| 1 | `figureEight` | The famous figure-8 orbit |
| 2 | `threeBodyChaos` | Nudge it by one part in a million… |
| 3 | `pythagoreanEjection` | …and a star is flung into space |
| 4 | `lagrangeBreakup` | Even a perfect triangle falls apart |

**Preview storyboard** (~25 s):

| Time | Clip | On screen |
|---|---|---|
| 0–8 s | `figureEight` | one full figure-8 loop |
| 8–18 s | `threeBodyChaos` | the nudged run and its twin drift apart |
| 18–25 s | `pythagoreanEjection` | close encounter; "Ejection" banner |

---

## Header and search results images

Creative assets per [Apple's asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
and the [creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications):

| Asset | Size | Art safe area (px) | Where it shows |
|---|---|---|---|
| Product page header | 21:9, **3840 × 1646** | 1646 × 661 at (1097, 493), centred | top of the product page |
| Search results | 3:2, **3840 × 2560** (min 1920 × 1280) | 2168 × 1030 at (836, 765), centred | Search tab, instead of screenshots |
| *Universal (not used)* | 16:9, 5244 × 2950, .png | 1402 × 962 at (1921, 660) | one image cropped into both |

Formats .jpeg/.jpg/.png, **no alpha channel**. The safe areas come from Apple's
Photoshop templates (the only part every device shows); everything outside them
may be cropped.

```bash
AppStore/capture-screenshots.sh --artwork               # both pages
AppStore/capture-screenshots.sh --artwork three-body    # one page
```

The Debug app freezes each scene at its capture moment and re-renders the canvas
offscreen at each asset's size (`Views/ArtworkExport.swift`): simulation only, with no
text, badges, centre-of-mass marker, habitable zone or app chrome. The images are opaque
PNGs. Each scene is zoomed so its trails and bodies fill 90% of the safe area, and
the spacetime grid fills the crop margins. Render scale: header 4× (on iPhone its safe
area spans the screen), search 8× (the card spans the screen), so lines keep their
in-app weight. Output: `AppStore/artwork/<scene>-<asset>.png` for every scene
(alternatives), plus the picks below, ready to upload:

| Page | Header | Search results |
|---|---|---|
| Black Holes | `black-holes-header.png` ← `horizonPlunge` (horizon, photon sphere and disk across the wide frame) | `black-holes-searchResults.png` ← `blackHoleVisual` (a planet orbiting the black hole) |
| Three-Body Problem | `three-body-header.png` ← `figureEight` | `three-body-searchResults.png` ← `figureEight` (same art in both strengthens recognition, per Apple) |

Picks are `ARTWORK_PICKS` in the script; change a pick there and rerun.

**Rules to keep in mind (Apple):** one clear idea per asset; nothing that
must stay visible outside the safe area; no prices, URLs, awards or other
platforms' logos; 4+ content. Text is optional ("a short phrase that enhances
your visual"); if you add one in Claude Design, keep it inside the safe area and
localize it. Check both images in App Store Connect's preview tool before submitting.

**Upload:** App Store Connect → the custom product page (or the version) → header
and search results assets; approved assets also land in the Asset Library.

---

## Deep links

Scheme `cosmicpath` (`CFBundleURLTypes` in `Info.plist`), handled by
`ContentView.onOpenURL` → `AppScenario(url:)`. Links ignore case and a trailing
slash. Unknown links just open the app. A link sets up the scene and starts it.

| Link | Opens |
|---|---|
| `cosmicpath://scenario/black-hole/visual` | Visual Black Hole Mode, stable orbit at 3.6 rₛ |
| `cosmicpath://scenario/black-hole/probe` | Realistic probe, eccentric rosette |
| `cosmicpath://scenario/black-hole/planet` | planet inside the Roche limit |
| `cosmicpath://scenario/black-hole/s2` | S2 around Sgr A* |
| `cosmicpath://scenario/three-body/figure-8` | Figure-8 |
| `cosmicpath://scenario/three-body/pythagorean` | Pythagorean problem |
| `cosmicpath://scenario/three-body/lagrange` | Lagrange triangle |
| `cosmicpath://scenario/three-body/sun-earth-moon` | Sun–planet–moon |
| `cosmicpath://scenario/three-body/chaos` | Pythagorean nudged by 10⁻⁶, with its twin |

Test on a simulator:

```bash
xcrun simctl openurl <UDID> cosmicpath://scenario/three-body/figure-8
```

iOS first asks "Open in "Simple Orbit Simulator"?" for a custom scheme; tap
Open. `CosmicPathSwiftUITests/DeepLinkUITests` covers cold and warm links, case
variants and an unknown link, and confirms that alert itself. Once the version
is live, check that the page's **Open** button goes straight into the scene on a
real device.

Universal links (`https://…`) would need a hosted `apple-app-site-association`
file and a website, so they're out of scope. When adding the deep link in App
Store Connect, check that the field accepts a custom-scheme URL. If it only takes
`https://` links, this is the point to set up a small site with universal
links.

---

## App update (next version)

**Keyword field** (100 / 100, comma-separated, no spaces after commas). It has no
words from the app name or subtitle; check this against the live name and subtitle
before submitting, and swap any word they contain for another:

```
black hole,three body,relativity,einstein,chaos,gravity,physics,astronomy,space,event horizon,kepler
```

**What's New** (134 characters):

> Open a scene straight from the App Store: black holes, the three-body problem and more. Also fixes the orbit count reading "1 orbits".

The version also fixes the Black Hole Mode switch resetting the strong-field
distances when a scene (or link) turned the mode on.

---

## App Store Connect checklist

Pages can go live on the current version (screenshots, text and keywords); the
deep links need the new version.

- [ ] Run `AppStore/capture-screenshots.sh` and check every PNG.
- [ ] Run `AppStore/capture-screenshots.sh --artwork`; upload each page's header and
      search results image and check them in the preview tool.
- [ ] Optional: frame the screenshots with captions; record and edit the previews.
- [ ] App Store Connect → the app → **Custom Product Pages** → **Create**.
  - [ ] Reference name `Black Holes`; promotional text; iPhone 6.3" and iPad 13"
        screenshots in the order above; preview video (optional).
  - [ ] Assign the page's keywords (they must already be in the version's keyword field).
  - [ ] Submit for review.
- [ ] Repeat for `Three-Body Problem`.
- [ ] Next version: update the keyword field and What's New, submit.
- [ ] Once that version is live: add each page's **deep link**.
- [ ] After 2–4 weeks: compare each page's conversion rate with the default page
      (App Analytics → filter by product page) and decide which page comes next.
