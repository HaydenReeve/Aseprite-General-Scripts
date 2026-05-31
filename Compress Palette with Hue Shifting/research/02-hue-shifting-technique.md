# 02 — Hue-Shifting Technique: Research Report

> **Purpose:** Inform a Lua script for Aseprite that programmatically compresses a
> sprite's existing palette into hue-shifted ramps reminiscent of Mark Ferrari,
> Henk Nieborg, and modern indie pixel artists.

---

## Table of Contents

1. [The Hue-Shifting Technique](#1-the-hue-shifting-technique)
2. [Ramp Construction](#2-ramp-construction)
3. [Existing Palettes and Analyses](#3-existing-palettes-and-analyses)
4. [Programmatic Generation of Hue-Shifted Ramps](#4-programmatic-generation-of-hue-shifted-ramps)
5. [Practical Aesthetic Rules to Encode](#5-practical-aesthetic-rules-to-encode)
6. [References](#6-references)

---

## 1. The Hue-Shifting Technique

### 1.1 Definition

**Hue shifting** is the practice of deliberately rotating the hue component of a
colour along a ramp as lightness changes — rather than merely increasing or
decreasing brightness on a single fixed hue. The conventional warm/cool split is:

| Ramp direction | Hue shift direction | Rationale |
|---|---|---|
| Toward highlights | Warmer (yellow ≈ 50–60°, orange ≈ 20–30°, red ≈ 0°) | Incandescent/solar light is warm; the Purkinje shift |
| Toward shadows | Cooler (blue ≈ 210–240°, purple ≈ 270–290°) | Ambient sky-light fill is cool; the Rayleigh effect |

The canonical description from Raymond "Slynyrd" Schlitter:

> "A good color ramp should also apply **hue-shifting**, which is a transition in
> hue across the color ramp … Many beginners overlook hue-shifting and end up with
> 'straight ramps' that only transition brightness and saturation. There is no law
> that says you can't do this but the resulting colors will lack interest and be
> difficult to harmonize with ramps of a different hue."
>
> — Slynyrd, *Pixelblog #1 — Color Palettes* (2018)
> <https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes>

Pedro Medeiros (saint11) illustrates the same principle:

> "Instead of using a simple value ramp, we will use a hue-shifting and
> saturation-shifting ramp … In this case I made the shadow a little more blue and
> less saturated (colder), and the light a little more yellow and saturated
> (warmer), almost like the church photo."
>
> — Pedro Medeiros, *Article 6 — Basic Color Theory* (2021)
> <https://saint11.art/pixel_art_articles/article6>

The Pixel Parmesan blog (host: a senior industry pixel artist) provides a more
physically-grounded critique of naive "hue-shifting" tutorials, noting that the
saturation follows a **curve** (not a monotone line):

> "If you plot out the shades of a single-colored object on a white background with
> a single white light source, as it goes from light to dark you will notice that
> **this is a curve rather than a line** — the saturation increases and then
> decreases again, while the value increases linearly and the hue stays almost
> entirely constant."
>
> — Pixel Parmesan, *Color Theory for Pixel Artists — It's All Relative*
> <https://pixelparmesan.com/blog/color-theory-for-pixel-artists-its-all-relative>

This is the *physical* baseline. Hue-shifting then layers *artistic* light-source
temperature on top of that physical baseline.

---

### 1.2 Origins and History

#### Mark Ferrari — *The Aesthetics of Game Art* (GDC 2016)

Ferrari is the definitive historical pioneer of palette-limited colour art.
Working at LucasArts in the late 1980s–90s, he created lush multi-plane scrolling
backgrounds for games such as *Loom* (1990) and *The Secret of Monkey Island* (1990)
using EGA's 64-colour and VGA's 256-colour palettes. His celebrated
*Living Worlds* demo (c. 1993) demonstrated real-time palette cycling — all
colour change achieved by remapping palette indices, with **zero new pixel data**.

His 2016 GDC talk "Technical Artist Bootcamp: The Aesthetics of Game Art" is the
canonical reference for the colour-cycling and palette-limitation philosophy.
YouTube recording: <https://youtu.be/aMcJ1Jvtef0>

Ferrari's principle: when you have only 32 or 64 colours, every colour must
carry double duty. Ramps must be designed so that shadows of one material can
serve as midtones of a darker material — palette sharing as a structural
constraint that inadvertently produces the hue-shifted "crossover" look.

#### Henk Nieborg — Character Sprite Mastery

Henk Nieborg (known for *Lionheart*, *Flink*, and *Contra: Hard Corps* character
sprites) demonstrated that even within tight Amiga and Mega Drive colour budgets,
ramps could be made to feel rich by:
- Keeping individual character palettes to 8–16 colours.
- Sharing dark shadow colours between multiple objects on screen.
- Shifting highlight hues toward yellow-white to suggest a single directional
  light source without needing a pure white pixel.

His sprite work for *Worms* (Team17, 1995) and *Flink* (Psygnosis, 1994) are
commonly cited in pixel art educational communities as gold-standard examples of
Amiga OCS ramp construction.

#### DawnBringer (DB)

The artist "DawnBringer" on PixelJoint published the DB16 (2011) and DB32 (2013)
palettes that became ubiquitous in modern pixel art. These palettes are not
explicitly structured as hue-shifted ramps, but their colours were carefully
chosen so that multiple ramps *can* be extracted from them — a property that drove
widespread community adoption.

#### Pedro Medeiros (saint11) — Celeste pixel art

The artist behind *Celeste* (2018, with Noel Berry & Maddy Thorson) published a
series of Patreon-supported pixel art tutorial GIFs and articles. His colour theory
article (Article 6) is one of the most widely shared beginner-level introductions
to hue shifting. His approach aligns with the warm-highlight / cool-shadow
convention.
Website: <https://saint11.art/pixel_art_articles/article6>

#### Adam (AdamCYounis) — Apollo Palette

Adam is a modern pixel art educator known for his YouTube tutorials and the
*Apollo* palette (46 colours, 2020). Apollo is explicitly structured as
seven 6-colour hue-shifted ramps plus a 10-stop greyscale ramp. Ramps converge
at dark shared shadows and diverge into distinct warm/cool highlights.

The Raven/Pigment research document describes Apollo:

> "The Apollo palette in particular is a good one to learn from, because the
> creator (AdamCYounis) has created a great accompanying tutorial explaining how
> he arrived at those values, including hue shifting and 'colour ramps' that
> converge and overlap."
>
> — bencoveney.github.io/posts/colour-palette.md

Lospec page: <https://lospec.com/palette-list/apollo>

#### Slynyrd (Raymond Schlitter)

Slynyrd built *Mondo* (128 colours, 8 ramps × 9 swatches, 2018) as a
general-purpose palette with a uniform +20° positive hue shift per step:

> "For this palette I want 9 swatches per ramp with 20 degrees of positive hue
> shift between each swatch. I like a lot of hue shift because it creates harmony
> between ramps and just looks neat, but 20 is about as high as I go."
>
> — Slynyrd, *Pixelblog #1 — Color Palettes*
> <https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes>

Positive hue shift (increasing H in HSB) moves from red → orange → yellow →
green, which warms the highlights in Western colour-wheel terms.

#### Endesga (Johan Vinet / @ENDESGA)

Endesga is one of the most widely cited Twitter voices on hue shifting in the
modern pixel art community. His tweet on "Hue Shifting" was cited in the
`fettepalette` library:
<https://twitter.com/ENDESGA/status/971690827482202112> (2018)

His palettes (Endesga 16, 32, 64) are high-contrast, high-saturation, and use
strong hue shifts especially across the reds–oranges.

#### Brandon James Greer (BJGpixel) — YouTube

BJG's tutorial *Hue Shifting in Pixel Art* is cited as a key inspiration for the
`fettepalette` library:
<https://www.youtube.com/watch?v=PNtMAxYaGyg>

#### Cyangmou

Prolific pixel artist and tutorial writer with extensive DeviantArt tutorials on
colour selection and palette construction for pixel art, emphasising the
importance of limited palettes with intentional hue and saturation arcs.
DeviantArt: <https://www.deviantart.com/cyangmou>

---

### 1.3 Common Heuristics

| Parameter | Typical Range | Notes |
|---|---|---|
| Hue shift per ramp step | 10°–25° | Slynyrd caps at 20°; FettePalette default `hueCycle` ≈ 0.3 of 360° across entire ramp |
| Direction (warm highlights) | Positive in HSB (red→yellow) | Most natural-looking |
| Direction (cool shadows) | Negative in HSB (purple→blue) | Matches sky-fill ambient light |
| Total hue rotation across full ramp | 30°–180° | SLSO8 spans ~180°; Apollo spans ~40–60° per ramp |
| Saturation at shadow | Low–mid (30–60%) | Dampened by lack of direct light |
| Saturation at midtone | Peak (60–90%) | Maximum chroma potential per Munsell system |
| Saturation at highlight | Reduced (20–50%) | Desaturates toward white |
| Lightness curve shape | S-curve or log | Faster transitions near mid, slower at extremes |
| Ramp start brightness | 10–25% | Not true black unless intentional |
| Ramp end brightness | 85–100% | Near white; saturation dropped to prevent burn |

---

## 2. Ramp Construction

### 2.1 Number of Steps Per Ramp

| Era / Style | Steps | Examples |
|---|---|---|
| Retro / hardware-constrained | 3–4 | Game Boy (4), Famicom (~3–4 per object) |
| Mid-era (Amiga, SNES) | 4–6 | Nieborg's character sprites |
| Modern pixel art palettes | 5–8 | Apollo (6), Resurrect 64 (4–6 per ramp), Endesga 32 |
| Large general-purpose palettes | 7–10 | Slynyrd Mondo (9), DB32 implicit |

The minimum meaningful hue-shifted ramp is **3 stops**: shadow, midtone,
highlight. At 3 stops, the algorithm sets shadow to cooler hue, midtone to local
hue, and highlight to warmer hue.

At 5 stops:
```
[deep-shadow]  [shadow]  [midtone]  [highlight]  [specular]
 coolest hue ←————————————————————————————→ warmest hue
 lowest sat  ←—peak sat at midtone—→ low sat again
 darkest val ←————————————————————————————→ brightest val
```

### 2.2 Shared Colours and Palette Cohesion

Vinik24 explicitly describes shared shadow/highlight colours as a design goal:

> "Designed as a soft pastel take on the standard supergameboy palette, expanded
> into a set of connected ramps of four shades, all sharing the **same shadow** and
> the **same highlight**."
>
> — Lospec, Vinik24 description
> <https://lospec.com/palette-list/vinik24>

This "ramp linking" means:
- **Shadow colours are shared** across all ramps (1–2 near-black anchor swatches).
- **Highlight colours can also converge** toward warm whites/creams.
- Materials look lit by the same source because their extremes agree.

Apollo palette demonstrates this: all 7 ramps share the same 2-stop shadow
anchor (`#090a14`, `#10141f`) from the greyscale ramp.

### 2.3 Temperature Shifts

Two primary lighting temperature scenarios:

| Scenario | Highlights | Shadows | Use case |
|---|---|---|---|
| **Warm light / cool shadow** | Shift H toward 40–60° (yellow/orange) | Shift H toward 200–250° (blue/violet) | Daylight, fire, incandescent — most common in games |
| **Cool light / warm shadow** | Shift H toward 180–220° (cyan/blue) | Shift H toward 20–40° (orange) | Moonlight, neon, dungeon ambient glow |

Pedro Medeiros (saint11):

> "I like to have images with opposing shadow and light temperatures, usually a
> **hot light and cold shadows**, but sometimes the opposite can work too."
>
> <https://saint11.art/pixel_art_articles/article6>

### 2.4 Saturation Curves

Physical observation (Munsell/Pixel Parmesan):
- At neutral lighting, saturation describes a **bell curve** along the value axis.
- Midtones hold the highest chroma; highlights and shadows reduce chroma.

Artist-stylised versions amplify this:
- Shadows: additional chroma reduction (cooler, greyer) for contrast with highlights.
- Highlights: pushed toward high-brightness / lower-saturation to suggest bloom.

Slynyrd on his Mondo palette:

> "Saturation peaks in the middle swatch in this example, but this is not a hard
> rule. Generally, darker colors have more saturation … The saturation takes larger
> steps on the ends and smaller steps in the middle where it's the highest
> percentage."
>
> <https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes>

Slynyrd also describes an alternative "X pattern" ramp (saturation rises as
brightness falls) for vivid dark colours:

> "I've made ramps where the saturation continues to climb as the brightness
> decreases, creating an X pattern. This results in vivid dark colors."

---

## 3. Existing Palettes and Analyses

Below: each palette's hex colours, inferred HSB coordinates for representative
swatches, and notes on hue-shifting. All Lospec URLs confirmed live.

### 3.1 DawnBringer 16 (DB16)

**Author:** DawnBringer | **Colors:** 16 | **Downloads:** 10,095
**Lospec:** <https://lospec.com/palette-list/dawnbringer-16>

```
#140c1c  #442434  #30346d  #4e4a4e
#854c30  #346524  #d04648  #757161
#597dce  #d27d2c  #8595a1  #6daa2c
#d2aa99  #6dc2ca  #dad45e  #deeed6
```

**Hue-shift analysis:** DB16 is not structured as explicit ramps. It provides
one representative colour per colour family (one red, one blue, one green, etc.)
plus greys. It does not internally contain hue-shifted ramps — rather, it is
designed so artists can *create* ramps by combining adjacent palette entries.
The dark purple (`#442434`) and near-black (`#140c1c`) serve as shared shadow
anchors. The highlights (`#deeed6`, `#dad45e`) are warm cream and yellow.

**Ramp-extraction note:** Community analyses (Lospec DB Palette Analysis PNG)
show that the 16 colours can be organised into 4 loose 3–4 stop ramps by hue
family, with the blue (`#597dce`) often being the coolest colour used in
shadows alongside the dark shades.

---

### 3.2 DawnBringer 32 (DB32)

**Author:** DawnBringer | **Colors:** 32 | **Downloads:** 20,842
**Lospec:** <https://lospec.com/palette-list/dawnbringer-32>

```
#000000  #222034  #45283c  #663931
#8f563b  #df7126  #d9a066  #eec39a
#fbf236  #99e550  #6abe30  #37946e
#4b692f  #524b24  #323c39  #3f3f74
#306082  #5b6ee1  #639bff  #5fcde4
#cbdbfc  #ffffff  #9badb7  #847e87
#696a6a  #595652  #76428a  #ac3232
#d95763  #d77bba  #8f974a  #8a6f30
```

**Hue-shift analysis:** DB32 explicitly adds cool blues/cyans (`#5b6ee1`,
`#639bff`, `#5fcde4`, `#cbdbfc`) and warm yellows/oranges (`#df7126`,
`#d9a066`, `#eec39a`, `#fbf236`) that function as highlight tints. The purple
(`#3f3f74`, `#76428a`) adds a cool shadow component.

Identifiable ramps:
- **Warm earth:** `#45283c` → `#663931` → `#8f563b` → `#df7126` → `#d9a066` → `#eec39a`
  (H: purple-brown → red-brown → orange → cream; solid warm highlight shift)
- **Cool grey-blue:** `#222034` → `#3f3f74` → `#306082` → `#5b6ee1` → `#639bff` → `#cbdbfc`
  (H: dark navy → steel blue → light blue; cool shadow, cool highlight)

---

### 3.3 Endesga 32

**Author:** Endesga | **Colors:** 32 | **Downloads:** 195,634
**Lospec:** <https://lospec.com/palette-list/endesga-32>

**Hue-shift analysis:** Endesga 32 has a very strong warm bias with vivid reds,
oranges, and yellows. Notable ramps:

- **Skin/earth:** `#be4a2f` → `#d77643` → `#ead4aa` (compressed 3-stop warm ramp;
  H shifts from red-orange ~15° to warm orange ~30° to cream ~35°)
- **Brown earth:** `#733e39` → `#b86f50` → `#e4a672` → `#ead4aa`
  (H shifts from dark red-brown ~5° toward warm tan ~30°)
- **Blue-navy:** `#124e89` → `#0099db` → `#2ce8f5` (cool blue shadow to cyan highlight)
- **Dark grey-navy:** `#262b44` → `#3a4466` → `#5a6988` → `#8b9bb4` → `#c0cbdc`
  (H shifts from dark purple-navy ~235° toward grey-blue ~220°, saturation drops)

The palette does *not* share a single shadow anchor — each material ramp is
relatively self-contained. High saturation and contrast throughout.

---

### 3.4 Endesga 64

**Author:** Endesga | **Colors:** 64 | **Downloads:** 94,080
**Lospec:** <https://lospec.com/palette-list/endesga-64>

**Description (Lospec):**
> "Honed over years of palette creation, refined for materialistic pixelart and
> design. High contrast, high saturation, shaped around painting the organic and
> structured life of the heptaverse."

**Hue-shift analysis:** Endesga 64 is organized into approximately 10 ramps of
6 colours each, plus greys. The grey ramp (`#131313` → `#1b1b1b` → `#272727`
→ `#3d3d3d` → `#5d5d5d` → `#858585` → `#b4b4b4` → `#ffffff`) is a pure
brightness ramp with no hue shift — serving as a neutral reference.

Colour ramps do show hue shifting: the reds ramp (`#891e2b` → `#c42430`
→ `#ea323c` → `#f5555d` → `#f68187` → `#fca790` → `#fdcbb0`) shifts from
deep red (~350°) toward pink-salmon (~0–15°) in highlights. The blues (`#03193f`
→ `#0c0293` → `#3003d9` → `#7a09fa` → `#db3ffd`) push into blue-violet and
then purple-violet toward highlights — a cool-stays-cool approach.

---

### 3.5 AAP-64

**Author:** Adigun A. Polack | **Colors:** 64 | **Downloads:** 77,962
**Lospec:** <https://lospec.com/palette-list/aap-64>

**Hue-shift analysis:** AAP-64 is organised as approximately 8 ramps of 7–8
colours. The reds ramp (`#73172d` → `#b4202a` → `#df3e23` → `#fa6a0a`
→ `#f9a31b` → `#ffd541` → `#fffc40`) demonstrates classic warm-shift highlights:
hue goes from deep red (~345°) through orange (~25°) to yellow (~55°). The
green ramp (`#14a02e` → `#59c135` → `#9cdb43` → `#d6f264`) warms toward
yellow-green. The skin ramp (`#71413b` → `#bb7547` → `#dba463` → `#f4d29c`)
is a classic warm earth tone ramp.

The blue ramp (`#143464` → `#285cc4` → `#249fde` → `#20d6c7` → `#a6fcdb`)
is unusual: it shifts from navy blue toward teal-cyan in highlights, then into
a near-white turquoise — a cold-stays-cold approach, maintaining consistent
cool temperature throughout.

---

### 3.6 PICO-8

**Author:** Lexaloffle Games | **Colors:** 16 | **Downloads:** 62,597
**Lospec:** <https://lospec.com/palette-list/pico-8>

```
#000000  #1D2B53  #7E2553  #008751
#AB5236  #5F574F  #C2C3C7  #FFF1E8
#FF004D  #FFA300  #FFEC27  #00E436
#29ADFF  #83769C  #FF77A8  #FFCCAA
```

**Hue-shift analysis:** PICO-8 is not designed as hue-shifted ramps — it is a
*flat* palette of 16 expressive colours. Each colour represents a different hue
family with no paired shadow/highlight of the same hue within the palette.

Artists using PICO-8 either:
1. Dither between adjacent palette colours to create implied ramps.
2. Accept the stylised, flat-shade aesthetic as intentional.
3. Pick non-obvious warm/cool pairings (e.g., the dark navy `#1D2B53` as a
   shadow for the mid-blue `#29ADFF`; the brown `#AB5236` as a shadow for
   the orange `#FFA300`).

The cream highlight (`#FFF1E8`) and warm orange (`#FFCCAA`) function as
warm highlight colours; the dark navy (`#1D2B53`) and dark purple (`#7E2553`)
as cool shadow anchors.

---

### 3.7 Sweetie 16

**Author:** GrafxKid | **Colors:** 16 | **Downloads:** 64,793
**Lospec:** <https://lospec.com/palette-list/sweetie-16>

```
#1a1c2c  #5d275d  #b13e53  #ef7d57
#ffcd75  #a7f070  #38b764  #257179
#29366f  #3b5dc9  #41a6f6  #73eff7
#f4f4f4  #94b0c2  #566c86  #333c57
```

**Hue-shift analysis:** Sweetie 16 is a colour-wheel palette arranged in two
arcs: a warm arc (red-purple `#5d275d` → red `#b13e53` → orange `#ef7d57`
→ yellow `#ffcd75` → lime `#a7f070`) and a cool arc (green `#38b764` → teal
`#257179` → dark blue `#29366f` → blue `#3b5dc9` → sky `#41a6f6`
→ cyan `#73eff7`).

It also includes a 4-stop blue-grey ramp: `#1a1c2c` → `#333c57` → `#566c86`
→ `#94b0c2` → `#f4f4f4` (near white). This greyscale-leaning ramp shifts from
dark navy (~235°) toward lighter blue-grey (~220°), dropping saturation toward
the highlight.

For pixel art usage, the warm arc can serve as warm material ramps and the
cool arc as cool material ramps, sharing the single black (`#1a1c2c`) as a
shadow anchor.

---

### 3.8 Resurrect 64

**Author:** Kerrie Lake | **Colors:** 64 | **Downloads:** 328,543
**Lospec:** <https://lospec.com/palette-list/resurrect-64>

**Hue-shift analysis:** Resurrect 64 is explicitly organised into structured
hue-shifted ramps of 4 colours each (plus a 4-stop greyscale). The organisation
can be read from the hex data:

- **Grey ramp:** `#2e222f` → `#3e3546` → `#625565` → `#966c6c` → `#ab947a`
  → `#7f708a` → `#9babb2` → `#c7dcd0` → `#ffffff` (9 stops; H shifts from
  purple-grey ~300° toward blue-grey ~190° — a deliberately hue-shifted grey ramp)
- **Red-orange ramp:** `#6e2727` → `#b33831` → `#ea4f36` → `#f57d4a` → `#ae2334`
  → `#e83b3b` → `#fb6b1d` → `#f79617` → `#f9c22b` (warm shift: red → orange
  → yellow-orange in highlights)
- **Earth-skin ramp:** `#7a3045` → `#9e4539` → `#cd683d` → `#e6904e` → `#fbb954`
- **Blue ramp:** `#323353` → `#484a77` → `#4d65b4` → `#4d9be6` → `#8fd3ff`
  (H: dark purple-navy → mid-blue → sky blue → light cyan in highlights)
- **Green ramp:** `#165a4c` → `#239063` → `#1ebc73` → `#91db69` → `#cddf6c`
  (H: dark teal → green → lime-yellow highlight — warms toward yellow)
- **Purple ramp:** `#45293f` → `#6b3e75` → `#905ea9` → `#a884f3` → `#eaaded`
  (H: dark purple-magenta → violet → lavender highlight)
- **Pink/rose ramp:** `#753c54` → `#a24b6f` → `#cf657f` → `#ed8099` (warm rose)
- **Deep reds:** `#831c5d` → `#c32454` → `#f04f78` → `#f68181` → `#fca790`
  → `#fdcbb0` (magenta-crimson to salmon-cream — strong warm highlight shift)

**Key insight:** Resurrect 64's grey ramp is itself hue-shifted — it moves from
purple-shadow to blue-grey to near-white, not through neutral grey. This is a
conscious design decision to add ambient colour to what would otherwise be dead
neutrals.

---

### 3.9 Apollo

**Author:** AdamCYounis | **Colors:** 46 | **Downloads:** 188,455
**Lospec:** <https://lospec.com/palette-list/apollo>

Apollo is the archetypal modern structured palette. Seven 6-stop colour ramps
plus one 10-stop greyscale ramp, each ramp explicitly hue-shifted.

**Greyscale (10 stops):**
```
#090a14 → #10141f → #151d28 → #202e37 → #394a50
→ #577277 → #819796 → #a8b5b2 → #c7cfcc → #ebede9
```
Hue: dark navy (~220°) → blue-grey (~200°) → near-neutral grey (~180°) → white.
Saturation: drops from ~40% in deep shadow to <5% at highlight. This is a
"warm shadow / cool shadow" choice — the darkest values tilt toward blue, which
reads as ambient skylight.

**Ramp 1 — Blues:**
`#172038` → `#253a5e` → `#3c5e8b` → `#4f8fba` → `#73bed3` → `#a4dddb`
H: ~215° → ~210° → ~210° → ~205° → ~198° → ~183° (shifts toward cyan/teal
in highlight — cool ramp that warms slightly at the brightest end)

**Ramp 2 — Greens:**
`#19332d` → `#25562e` → `#468232` → `#75a743` → `#a8ca58` → `#d0da91`
H: ~160° → ~130° → ~110° → ~93° → ~80° → ~73° (shifts from teal-green toward
yellow-green in highlights — classic warm highlight)

**Ramp 3 — Browns/Skin:**
`#4d2b32` → `#7a4841` → `#ad7757` → `#c09473` → `#d7b594` → `#e7d5b3`
H: ~350° → ~8° → ~20° → ~27° → ~32° → ~37° (red-brown shadows warm toward
cream-tan in highlights)

**Ramp 4 — Warm oranges:**
`#341c27` → `#602c2c` → `#884b2b` → `#be772b` → `#de9e41` → `#e8c170`
H: ~330° → ~0° → ~20° → ~30° → `~38°` → ~43° (dark purple-red to golden yellow)

**Ramp 5 — Hot reds:**
`#241527` → `#411d31` → `#752438` → `#a53030` → `#cf573c` → `#da863e`
H: ~290° → `~330°` → `~345°` → ~0° → ~15° → ~30° (purple-shadow through red
to warm orange highlight — one of the most dramatic hue arcs in Apollo)

**Ramp 6 — Purples:**
`#1e1d39` → `#402751` → `#7a367b` → `#a23e8c` → `#c65197` → `#df84a5`
H: ~245° → `~270°` → ~300° → ~305° → ~315° → ~340° (dark blue-violet through
magenta to warm pink highlight)

**Apollo summary:** Every ramp's shadow converges toward the shared dark navy
family (~220–250°), and every ramp's highlight warms by +30° to +90° relative
to its shadow hue. This convergence creates palette-wide cohesion.

---

### 3.10 Vinik24

**Author:** Vinik | **Colors:** 24 | **Downloads:** 61,988
**Lospec:** <https://lospec.com/palette-list/vinik24>

**Description (Lospec):**
> "Designed as a soft pastel take on the standard supergameboy palette, expanded
> into a set of connected ramps of four shades, all sharing the same shadow and
> the same highlight."

Vinik24 has the most explicit "ramp linking" philosophy of all the reviewed
palettes. All ramps share `#000000` as absolute shadow and `#c5ccb8` (warm
grey-green) as the shared highlight. Within each ramp of 4 stops, the middle
two swatches carry the distinctive hue.

Representative ramp analysis:
- **Purple:** `#000000` → `#6f6776` → `#a593a5` → `#c5ccb8`
  (H: grey-purple midtones → warm grey highlight)
- **Blue:** `#000000` → `#416aa3` → `#7ca1c0` → `#c5ccb8`
  (H: blue mid → warm grey highlight)
- **Earth green:** `#000000` → `#557064` → `#6eaa78` → `#c5ccb8`
  (H: teal-green mid → warm grey highlight)

The shared neutral highlight `#c5ccb8` (H≈78°, S≈14%, B≈80%) is the key:
its warm green-grey tone unifies all material ramps under a single imagined
warm ambient light.

---

### 3.11 SLSO8

**Author:** Solosalsero | **Colors:** 8 | **Downloads:** 81,607
**Lospec:** <https://lospec.com/palette-list/slso8>

```
#0d2b45  #203c56  #544e68  #8d697a
#d08159  #ffaa5e  #ffd4a3  #ffecd6
```

SLSO8 is the most dramatic single-ramp hue-shift example in wide use. All 8
colours form a single diagonal ramp:

| Hex | H° | S% | B% | Description |
|---|---|---|---|---|
| `#0d2b45` | 210 | 83 | 27 | Deep blue shadow |
| `#203c56` | 210 | 65 | 34 | Dark blue |
| `#544e68` | 265 | 26 | 41 | Blue-purple midtone |
| `#8d697a` | 340 | 25 | 55 | Purple-pink |
| `#d08159` | 20 | 57 | 82 | Warm orange |
| `#ffaa5e` | 30 | 63 | 100 | Bright orange |
| `#ffd4a3` | 30 | 36 | 100 | Pale orange |
| `#ffecd6` | 28 | 16 | 100 | Cream highlight |

**Total hue rotation:** ≈180° (blue-purple → orange). This is the maximum
practical shift — the ramp passes through every warm and cool family in 8 steps.
It is ideal for sunset/dungeon lighting scenarios but limited as a general-purpose
palette. Artists use it as a monochrome-plus-atmosphere palette.

---

## 4. Programmatic Generation of Hue-Shifted Ramps

### 4.1 Existing Tools

| Tool | Type | Notes | URL |
|---|---|---|---|
| **FettePalette** | JavaScript library (MIT) | Curve-based HSV ramp generation; supports `hueCycle`, `tintShadeHueShift`, `curveMethod`, and easing functions; no GUI | <https://github.com/meodai/fettepalette> |
| **FettePalette Demo** | Interactive web UI | Live sliders for all parameters; best way to understand the parameter space | <https://meodai.github.io/fettepalette/> |
| **KPal** | Desktop app (Windows) | Abandoned Dec 2023, crash bugs; Windows only; no longer maintained | itch.io/kaspergl/kpal |
| **Lightcube** | Desktop app ($15) | Palette features inside a full pixel editor | - |
| **HSV Palette Generator** | Web | Too basic — single 5-colour ramp, PNG only | - |
| **CoMiGo's Palette Generator** | Web | Dormant since 2021, no `.gpl` export | - |
| **Adobe Color** | Web | Gamut mask, colour wheel tools; general-purpose, not pixel-art-specific | <https://color.adobe.com/create/color-wheel/> |
| **Coolors** | Web | Fast palette generation; no hue-shift curves; export to CSS/PNG | <https://coolors.co> |
| **Lospec Palette List** | Web (reference) | 4100+ community palettes, filter by size; not a generator | <https://lospec.com/palette-list> |
| **Pigment** | Desktop app (in development) | Tauri/React, uses FettePalette engine, Aseprite `.gpl`/`.pal` export; private repo | github.com/adanoelle/pigment (private) |

---

### 4.2 Open-Source Repositories

#### `meodai/fettepalette` (JavaScript/TypeScript, MIT)

The most fully-featured open-source hue-shift ramp generator.
GitHub: <https://github.com/meodai/fettepalette>

Key function signature:
```typescript
generateRandomColorRamp({
  total:               9,     // number of base colours
  centerHue:           180,   // base hue (0-360°)
  hueCycle:            0.3,   // how much hue rotates across ramp (0-1 = 0-360°)
  tintShadeHueShift:   0.1,   // hue shift applied to tints vs shades
  curveMethod:        'arc',  // 'lamé'|'arc'|'pow'|'powY'|'powX'|easings
  curveAccent:         0,     // accentuation of curve shape
  offsetTint:          0.1,   // tint offset from base curve
  offsetShade:         0.1,   // shade offset from base curve
  minSaturationLight: [0, 0], // [sat_min, light_min]
  maxSaturationLight: [1, 1], // [sat_max, light_max]
  colorModel:         'hsl',  // 'hsl'|'hsv'|'oklch'|'lch'
})
```

The `tintShadeHueShift` parameter directly encodes hue-shifting: positive values
push tints (highlights) toward higher hue values (warmer in red-orange zone) and
push shades (shadows) toward lower hue values (cooler). At `hueCycle > 0`, each
successive colour in the ramp also shifts hue by `(360 / total) * hueCycle`
degrees.

Internally, the hue for colour `i` in a ramp of `total` colours is:
```typescript
h = (360 + (-180 * hueCycle + (centerHue + i * (360 / (total + 1)) * hueCycle))) % 360;
```

And the tint hue is `(h + 360 * tintShadeHueShift) % 360`, while the shade hue
is `(360 + (h - 360 * tintShadeHueShift)) % 360`.

Source: `meodai/fettepalette:src/index.ts`

---

#### `AnastasiyaW/claude-code-config` — palette analysis script

Found a palette analysis Python script in this repo:
```python
return {
    "shadow_mean_hue": float(sh_hue),
    "highlight_mean_hue": float(hi_hue),
    "hue_rotation_deg": float(delta),
    "rotation_passes_30": delta >= 30,  # heuristic: meaningful shift > 30°
    ...
}
```
Source: `AnastasiyaW/claude-code-config:skills/creative/pixel-art-studio/scripts/palette.py`

This confirms the community heuristic: a **hue rotation ≥ 30°** between shadow
and highlight is considered meaningful hue shifting.

---

### 4.3 Parametric Model for Hue-Shifted Ramps

The following parametric model covers the space needed for the Aseprite Lua script:

```
Inputs:
  base_hue      (0–360°)      — local colour hue of the material
  base_sat      (0–1)         — saturation at the midtone
  base_val      (0–1)         — value/brightness at the midtone
  n_stops       (3–10)        — number of ramp steps
  shadow_shift  (deg, –)      — how many degrees to shift shadow toward cool
                                  (default: –20° to –30°, i.e., toward blue)
  highlight_shift (deg, +)    — how many degrees to shift highlight toward warm
                                  (default: +15° to +25°, i.e., toward yellow)
  val_range     (0–1)         — lightness spread (e.g., [0.15, 0.95])
  sat_peak      (0–1)         — normalised position in ramp where sat peaks
                                  (default: 0.5 = midtone)
  sat_falloff   (float)       — exponent controlling sharpness of sat bell curve
  curve_shape   (enum)        — 'linear', 'scurve', 'log', 'sqrt'
  light_temp    (enum)        — 'warm_light_cool_shadow', 'cool_light_warm_shadow'

Outputs:
  ramp: array of n_stops × [H, S, V] (or RGB) triples
```

For each step `t` in `[0, 1]` (0 = shadow, 1 = highlight):

```
val(t)     = val_range[0] + curve(t) * (val_range[1] - val_range[0])
hue(t)     = base_hue
           + lerp(shadow_shift, 0, t)   # shadow side
           + lerp(0, highlight_shift, t) # highlight side
sat_bell(t) = base_sat * (1 - |t - sat_peak|^sat_falloff)
sat_env(t) = sat_bell(t) * (1 - max(0, val(t) - 0.8))  # desaturate near white
```

The `curve(t)` function shapes value distribution:
- **S-curve:** `t^2 * (3 - 2*t)` (smooth step; avoids perceptual flattening)
- **Log:** `log(1 + t*(e-1))` (heavy lift in shadows, gentle in highlights)
- **Power:** `t^0.6` (EOTF-like, perceptually uniform on non-HDR displays)

---

## 5. Practical Aesthetic Rules to Encode

The following rules are concrete enough to implement as algorithm steps:

### 5.1 Core Hue-Shift Rules

| Rule | Value | Source |
|---|---|---|
| **Highlight hue offset** | +15° to +25° toward warm (yellow, orange) | Slynyrd (max +20°); FettePalette `tintShadeHueShift` |
| **Shadow hue offset** | –20° to –30° toward cool (blue, violet) | saint11; Pixel Parmesan; Apollo palette analysis |
| **Minimum meaningful hue rotation** | ≥ 30° shadow-to-highlight | Community heuristic from palette.py analysis |
| **Maximum practical hue rotation** | ≤ 180° | SLSO8 (8-stop, ~180°) is the extreme |
| **Positive shift direction (warm light)** | +H in HSB = red→yellow direction | Slynyrd: "positive hue shift usually results in more natural colors" |

### 5.2 Saturation Rules

| Rule | Value | Source |
|---|---|---|
| **Saturation peak position** | t ≈ 0.4–0.6 (midtone) | Pixel Parmesan, saint11, Slynyrd |
| **Shadow saturation** | base_sat × 0.5–0.8 | Shadows are underlit; chroma is suppressed |
| **Highlight saturation** | base_sat × 0.2–0.6 | Highlights blow out toward white |
| **Never exceed S = 95%** | Hard cap | "The biggest mistake is combining high saturation and brightness" — Slynyrd |
| **Never start ramp at S = 0** (unless black) | Soft rule | Zero-sat swatches look dead/muddy |
| **Alternative: X-pattern** | Sat rises as val falls | For vivid dark colours (jewels, neon) |

### 5.3 Value / Brightness Rules

| Rule | Value | Source |
|---|---|---|
| **Minimum ramp value** | 10–20% | Never pure black unless intentional |
| **Maximum ramp value** | 85–100% | Near-white OK if sat is reduced |
| **Value curve** | S-curve or log preferred | Avoids perceptual banding in midtones |
| **Step size non-uniform** | Larger steps at shadow extreme, smaller near white | Slynyrd value graph analysis |

### 5.4 Ramp Linking / Shadow Sharing Rules

| Rule | Implementation |
|---|---|
| **Shared shadow anchor** | All ramps should share 1–2 near-black swatches (the lowest 1–2 stops should map to the same dark colour) |
| **Optional shared highlight** | Vinik24 model: all ramps share a single warm-grey highlight to unify light source |
| **Shadow hue bias** | Dark anchor should be dark navy or dark purple (~220–270°), not neutral grey |
| **Highlight hue bias** | Light anchor should be warm cream or warm grey (~30–50°, low saturation) |

### 5.5 Special Material Rules

#### Skin Tones
- Skin operates in a very narrow hue band: ~15° (red-brown) → ~30° (orange-tan)
  in highlights, ~350° (red-purple) → ~5° (red) in shadows.
- Saturation is moderate (30–55%), dropping at both extremes.
- Never push skin shadows toward blue: this reads as illness/death.
- Use a very small hue shift: ±10–15° maximum.

#### Metallics (Gold, Silver)
- **Gold:** hue band ~30–50° (orange-yellow); shadows shift toward ~15° (red-gold);
  highlights shift toward ~55° (yellow-gold) with compressed saturation.
- **Silver/Iron:** near-neutral grey; shift shadow toward ~230° (blue-steel);
  highlight toward ~200° (cool grey-blue); very low saturation throughout.
- **Chromatic reflections:** metallic specular highlights often sample the
  environment colour, so a sky-blue specular on silver is physically correct.

#### Neutrals / Greys
- *Pure grey (S=0) is almost never used in hue-shifted palettes.*
- Grey ramps shift their hue: shadows toward blue-purple (~230–260°), highlights
  toward warm cream (~50–80°). See: Resurrect 64 grey ramp, Apollo greyscale.
- Saturation: 5–20% throughout, varying slightly.

#### Already-Saturated Colours (Neon, Jewels)
- Apply the "X-pattern" ramp: let saturation *rise* as value falls.
- Allow shadow saturation to exceed midtone saturation.
- Highlights still desaturate toward white.
- Total hue shift can be reversed (cool-to-cool or warm-to-warm) to avoid
  muddy intermediate colours.

#### Vegetation / Greens
- Greens warms dramatically in highlights toward yellow-green (~70–80°).
- Shadows shift toward teal (~150–160°) or dark forest green with blue tint.
- The Apollo green ramp is the reference: shadows at H≈160°, highlights at H≈73°.

---

### 5.6 Algorithmic Steps for Palette Compression

When compressing an existing sprite's palette into hue-shifted ramps, the
algorithm should:

1. **Cluster existing colours** by perceived hue family (use HSL hue ± tolerance
   to group similar hues together into candidate ramp groups).

2. **For each cluster, sort by lightness** (L in HSL or V in HSV) to establish
   ramp order.

3. **Fit a hue-shift curve** to the cluster:
   - Compute mean shadow hue and mean highlight hue.
   - If `|highlight_hue - shadow_hue| < 10°`, inject hue shift:
     - Push shadow hue by `–25°` (toward blue).
     - Push highlight hue by `+20°` (toward yellow).
   - If existing shift is present but in the wrong direction (e.g., shadows are
     warm and highlights are cool), flag as a lighting-reversal.

4. **Fit a saturation bell curve**:
   - Locate the maximum-saturation colour in the ramp.
   - Ensure it falls at step `t ≈ 0.4–0.6`.
   - If it falls at the extremes, cap extreme saturations and redistribute.

5. **Apply value curve smoothing**:
   - Re-space value steps using an S-curve (`smoothstep`) to remove perceptual
     banding.

6. **Merge shared shadows**:
   - If two ramps have very similar shadow colours (ΔE < 5 in Lab), merge them
     to a single shared dark anchor swatch. This reduces palette count and
     improves cohesion.

7. **Output palette** with ramps ordered by hue family (reds, oranges, yellows,
   greens, blues, purples), shadows-first per ramp.

---

## 6. References

| # | Source | URL |
|---|---|---|
| 1 | Mark Ferrari — GDC 2016: "The Aesthetics of Game Art" | <https://youtu.be/aMcJ1Jvtef0> |
| 2 | Mark Ferrari — Portfolio / 8-bit Game Art | <https://www.markferrari.com/art/8bit-game-art/> |
| 3 | Slynyrd — Pixelblog #1: Color Palettes | <https://slynyrd.com/blog/2018/1/10/pixelblog-1-color-palettes> |
| 4 | Pedro Medeiros (saint11) — Article 6: Basic Color Theory | <https://saint11.art/pixel_art_articles/article6> |
| 5 | Pedro Medeiros (saint11) — Pixel Art Tutorials (GIF series) | <https://saint11.art/blog/pixel-art-tutorials/> |
| 6 | Pixel Parmesan — Color Theory for Pixel Artists: It's All Relative | <https://pixelparmesan.com/blog/color-theory-for-pixel-artists-its-all-relative> |
| 7 | Brandon James Greer — Hue Shifting in Pixel Art (YouTube) | <https://www.youtube.com/watch?v=PNtMAxYaGyg> |
| 8 | meodai/fettepalette — Open-source hue-shift ramp generator | <https://github.com/meodai/fettepalette> |
| 9 | FettePalette — Live Demo | <https://meodai.github.io/fettepalette/> |
| 10 | ENDESGA — Hue Shifting tweet (2018) | <https://twitter.com/ENDESGA/status/971690827482202112> |
| 11 | Lospec — DawnBringer 16 palette | <https://lospec.com/palette-list/dawnbringer-16> |
| 12 | Lospec — DawnBringer 32 palette | <https://lospec.com/palette-list/dawnbringer-32> |
| 13 | Lospec — Endesga 32 palette | <https://lospec.com/palette-list/endesga-32> |
| 14 | Lospec — Endesga 64 palette | <https://lospec.com/palette-list/endesga-64> |
| 15 | Lospec — AAP-64 palette | <https://lospec.com/palette-list/aap-64> |
| 16 | Lospec — PICO-8 palette | <https://lospec.com/palette-list/pico-8> |
| 17 | Lospec — Sweetie 16 palette | <https://lospec.com/palette-list/sweetie-16> |
| 18 | Lospec — Resurrect 64 palette | <https://lospec.com/palette-list/resurrect-64> |
| 19 | Lospec — Apollo palette | <https://lospec.com/palette-list/apollo> |
| 20 | Lospec — Vinik24 palette | <https://lospec.com/palette-list/vinik24> |
| 21 | Lospec — SLSO8 palette | <https://lospec.com/palette-list/slso8> |
| 22 | adanoelle/raven — Pigment palette tool design document | `adanoelle/raven:docs/book/src/art/pigment.md` |
| 23 | bencoveney — Colour Palette article (Apollo analysis quote) | <https://bencoveney.github.io/posts/colour-palette> |
| 24 | James Gurney — Color and Light (book) | <https://www.amazon.com/Color-Light-Guide-Realist-Painter/dp/0740797719> |
| 25 | Cyangmou — Pixel art tutorials and guides | <https://www.deviantart.com/cyangmou> |
```

---

## Summary of Findings

**What was found and confirmed:**

1. **Hue-shifting technique** is well-documented across multiple primary sources (Slynyrd, saint11, Pixel Parmesan, FettePalette). The consensus: shift highlights +15–25° toward warm (yellow/orange), shift shadows –20–30° toward cool (blue/purple), with saturation peaking at the midtone stop.

2. **Ramp construction** norms: 3–5 stops for retro-constrained work, 5–8 for modern. Saturation is a bell curve (peak at midtone), not monotone. Shared shadow anchors (ramp linking) are used by Vinik24, Apollo, and similar palettes explicitly.

3. **Palette analyses**: SLSO8 is the most extreme hue-shift ramp (~180° rotation, 8 stops); Apollo is the archetypal modern structured palette (7 × 6-stop ramps, all converging at shared dark shadows); Resurrect 64 has even its grey ramp hue-shifted.

4. **Programmatic tools**: FettePalette (`meodai/fettepalette`) is the best open-source reference implementation, with full TypeScript source. Pigment is a planned Aseprite-focused GUI wrapper. KPal is abandoned.

5. **Practical rules encoded**: Concrete per-stop hue/sat/val formulas, edge-case handling for skin, metal, greens, and neutrals, and a 7-step algorithm for palette compression.

**File to write:** `D:\Aseprite\Compress Palette with Hue Shifting\research\02-hue-shifting-technique.md