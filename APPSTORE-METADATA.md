# Cartograph — Mac App Store Connect Metadata

## Identity

| Field | Value |
|-------|-------|
| **Name** | Cartograph |
| **Subtitle** | Fantasy World Map Generator |
| **Bundle ID** | com.cartograph.app |
| **SKU** | CARTOGRAPH-001 |
| **Platform** | macOS (Mac App Store) |
| **Primary Category** | Graphics & Design |
| **Secondary Category** | Entertainment |
| **Age Rating** | 4+ |
| **Price** | $4.99 (Tier 5) |
| **Availability** | All territories |

---

## Keywords

```
fantasy map,world map,procedural,cartography,map generator,worldbuilding,RPG map,map maker,portolan,game master
```

*(100 character limit)*

---

## Description

Cartograph generates procedural fantasy world maps that look hand-drawn by a historical cartographer — not produced by software. Every map is unique, rendered in the Age of Exploration portolan chart style using a 7-pass Metal GPU pipeline tuned for parchment texture, coastline calligraphy, and compass roses.

Writers, game designers, and worldbuilders use Cartograph to produce maps that feel like artifacts from the world they're building — not screenshots from a map editor.

HOW IT WORKS

Click Generate and Cartograph runs a full geophysical simulation: tectonic plate movement, hydraulic erosion, river networks, and a climate pipeline that places biomes by latitude and moisture. Settlements emerge from terrain suitability. The result is rendered in portolan style with IM Fell English and Cinzel Decorative typefaces — the same families used in 16th-century nautical charts.

FEATURES

• Procedural world generation: tectonics, erosion, rivers, climate, biomes
• Portolan chart renderer — 7-pass Metal GPU pipeline (macOS 14+, Metal 3)
• Settlement placement derived from terrain and climate suitability
• Manual override UI: adjust coastlines, place towns, rename regions
• Save and load maps as .cartograph document bundles (diff-friendly, version-control safe)
• Export at up to 4096×4096 pixels
• Offline-only: no network access, no accounts, no telemetry
• Bundled OFL fonts: IM Fell English + Cinzel Decorative

ONE-TIME PURCHASE

$4.99, once. No subscription. No in-app purchases. No cloud required.

---

## Promotional Text

*(Optional — appears above description, can be updated without a new app version)*

```
Generate a hand-drawn fantasy world map in seconds. Every world is different. Every map looks ancient.
```

---

## Support URL

https://github.com/saagpatel/Cartograph

---

## Privacy Policy URL

https://github.com/saagpatel/Cartograph/blob/main/PRIVACY.md

---

## Screenshots

### Required Sizes (Mac App Store)
- **1280 × 800 px** — 13" MacBook Air / MacBook Pro (non-Retina baseline)
- **1440 × 900 px** — 13" MacBook Pro Retina (2x: submit at 2880 × 1800 px)
- **2560 × 1600 px** — 16" MacBook Pro Retina (primary showcase size)

> Mac App Store requires at least one screenshot. Submit all three sizes for best device coverage.
> Retina sizes: double the logical resolution (1440×900 → submit 2880×1800; 2560×1600 → submit 5120×3200).

### Screenshot Plan (3–5 screenshots per size)

| # | Screen | App State | Headline Overlay |
|---|--------|-----------|------------------|
| 1 | Full map canvas | Freshly generated world — parchment background, coastlines in portolan ink style, Milky Way–style star border, compass rose prominent | "A world in seconds. A map for ages." |
| 2 | Terrain detail close-up | Zoomed to a mountain range — erosion ridgelines, river deltas meeting the coast, two settlements labeled in Cinzel Decorative | "Every river carved. Every peak earned." |
| 3 | Generation in progress | Sidebar showing tectonic simulation progress bar, partial terrain visible in canvas | "Geophysics first. Art second." |
| 4 | Manual override UI | Town placement popover open on a coastal tile, settlement name field active | "Your world. Your rules." |
| 5 | Export sheet | Export panel open, resolution set to 4096×4096, format PNG — finished map visible behind | "4096 × 4096. Print-ready." |

### How to Take Screenshots
1. Build and run Cartograph: `./script/build_and_run.sh --verify`
2. Launch the app and generate a world with a visually compelling result (retry a few times)
3. Resize the window to match the target screenshot dimensions before capturing
4. Use **Cmd+Shift+4** or `screencapture -l <window_id> screenshot.png` for pixel-accurate captures
5. For Retina screenshots: capture on a Retina display or use `screencapture -x` to get 2x resolution
6. Add marketing text overlays in Sketch, Figma, or Canva before uploading

### Local Captures

- `docs/media/appstore/cartograph-window-1280x800.png` — exact 1280×800 demo capture
- `docs/media/appstore/cartograph-window-1440x900.png` — exact 1440×900 demo capture derived from the 2560×1600 local capture
- `docs/media/appstore/cartograph-window-2560x1600.png` — exact 2560×1600 demo capture

These are local proof/demo captures. Final App Store screenshots still need
active-window polish, optional marketing overlays, and App Store Connect upload
validation before submission.

---

## App Review Notes

```
Cartograph is an offline-only macOS app. No network access, no accounts, no permissions required.

To test the core flow:
1. Launch the app — a blank canvas and sidebar appear
2. Click "Generate" in the sidebar to run the procedural world generation pipeline
3. Watch the terrain simulation progress (tectonic → erosion → climate → settlements)
4. The finished map renders in portolan chart style on the canvas
5. Zoom and pan the canvas using trackpad pinch/scroll gestures
6. Click any region or settlement to open the manual override popover
7. File → Save saves a .cartograph bundle to the chosen location
8. File → Export opens the resolution/format sheet

Generation takes approximately 3–8 seconds on Apple Silicon, longer on Intel Macs.
No special permissions, entitlements, or hardware are required.
```

---

## Checklist Before Submission

- [ ] Bundle ID `com.cartograph.app` registered in Apple Developer portal
- [x] App icon 1024×1024 appears correctly in Xcode asset catalog (no warnings; asset catalog added locally)
- [x] Archive succeeds locally: `make archive` writes `.derivedData/archives/Cartograph.xcarchive` with Apple Development signing
- [x] Hardened runtime enabled; strict `codesign` verification passes on the archive app
- [ ] Gatekeeper/App Store distribution assessment passes with distribution signing and notarization (Apple Development archive is expected to be rejected by `spctl`)
- [ ] Validate App passes with 0 errors (check entitlements — no unnecessary capabilities)
- [x] Local demo screenshots captured at 1280×800, 1440×900, and 2560×1600
- [ ] All final screenshots uploaded at correct Mac App Store sizes (1280×800, 1440×900, 2560×1600)
- [ ] Description, keywords, subtitle filled in App Store Connect
- [ ] Price set to $4.99 (Tier 5) in Pricing and Availability
- [ ] Age rating questionnaire complete (4+)
- [x] Support URL and Privacy Policy URL provided
- [x] PrivacyInfo.xcprivacy present (no network access, no data collected — minimal declaration)
- [x] Minimum deployment target set to macOS 14.0 in project settings
- [x] `.cartograph` document bundle UTI registered in Info.plist
- [ ] App Store export/TestFlight validation complete
- [ ] Notarization complete for non-App-Store distribution (`xcrun notarytool submit`)
- [ ] TestFlight (Mac) internal test complete (generate, save, export, reload)
- [ ] Submit for Review
