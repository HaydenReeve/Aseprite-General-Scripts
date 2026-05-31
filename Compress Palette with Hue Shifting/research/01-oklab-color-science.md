# OKLab / OKLCh Colour Science — Research Report
## For: Aseprite Palette Compression with Hue Shifting (Lua Script)
**File:** `01-oklab-color-science.md`  
**Date:** 2025  
**Scope:** OKLab fundamentals, perceptual distance metrics, palette quantisation algorithms, pixel-art-specific considerations.

---

## Table of Contents

1. [OKLab / OKLCh Fundamentals](#1-oklab--oklch-fundamentals)
   - 1.1 [Origins and Motivation](#11-origins-and-motivation)
   - 1.2 [Coordinate System and Geometry](#12-coordinate-system-and-geometry)
   - 1.3 [Exact Conversion Matrices and Code](#13-exact-conversion-matrices-and-code)
   - 1.4 [OKLCh: The Cylindrical Form](#14-oklch-the-cylindrical-form)
   - 1.5 [Comparison with Other Colour Spaces](#15-comparison-with-other-colour-spaces)
   - 1.6 [Known Pitfalls and Gotchas](#16-known-pitfalls-and-gotchas)
   - 1.7 [Gamut Mapping and Clipping in OKLab](#17-gamut-mapping-and-clipping-in-oklab)
2. [Perceptual Distance Metrics](#2-perceptual-distance-metrics)
   - 2.1 [Delta-E Variants](#21-delta-e-variants)
   - 2.2 [Euclidean Distance in OKLab as a ΔE Approximation](#22-euclidean-distance-in-oklab-as-a-δe-approximation)
   - 2.3 [Weighting Lightness vs Chroma vs Hue](#23-weighting-lightness-vs-chroma-vs-hue)
3. [Palette Quantisation Algorithms in Perceptual Spaces](#3-palette-quantisation-algorithms-in-perceptual-spaces)
   - 3.1 [Classic Algorithms](#31-classic-algorithms)
   - 3.2 [Implementations in CIELab / OKLab](#32-implementations-in-cielab--oklab)
   - 3.3 [Weighted k-Means with Pixel-Frequency Weights](#33-weighted-k-means-with-pixel-frequency-weights)
   - 3.4 [k-Means++ Seeding](#34-k-means-seeding)
4. [Pixel-Art Specific Considerations](#4-pixel-art-specific-considerations)
   - 4.1 [Why Pixel Art Resists Generic Quantisation](#41-why-pixel-art-resists-generic-quantisation)
   - 4.2 [Preserving Hard Edges, Avoiding Antialiasing Artefacts](#42-preserving-hard-edges-avoiding-antialiasing-artefacts)
   - 4.3 [Transparent and Partially-Transparent Pixels](#43-transparent-and-partially-transparent-pixels)
5. [Implementation Guidance for Lua/Aseprite](#5-implementation-guidance-for-luaaseprite)
6. [Citations](#6-citations)

---

## 1. OKLab / OKLCh Fundamentals

### 1.1 Origins and Motivation

OKLab was designed by **Björn Ottosson** and published on 23 December 2020 in the blog post *"A perceptual color space for image processing"* ([https://bottosson.github.io/posts/oklab/](https://bottosson.github.io/posts/oklab/)). By 2025 it has become an industry standard, appearing in Photoshop (default gradient interpolation), CSS Color Level 4/5, Unity, Godot, and countless open-source libraries.

Ottosson's stated design goals:

> - **Should be an opponent color space**, similar to CIELAB.
> - **Should predict lightness, chroma and hue well.** L, C and h should be perceived as orthogonal, so one can be altered without affecting the other two.
> - **Blending two colors should result in even transitions.**
> - **Should assume a D65 whitepoint.**
> - **Should behave well numerically** — easy to compute, numerically stable, differentiable.
> - **Should assume normal well-lit viewing conditions.**
> - **If scale/exposure of colors are changed, perceptual coordinates should just be scaled by a factor** (scale invariance, no dependence on absolute luminance).

The name is deliberately self-deprecating: it does "an OK job" and uses coordinates L, a, b.

**Structural approach:** OKLab shares the IPT architecture — two 3×3 matrix multiplications with a power-law nonlinearity in between — but its matrix parameters were derived by minimising prediction error against:
- CAM16-generated lightness/chroma data (the "gold standard" appearance model).
- The Ebner–Fairchild uniform-hue dataset (same data used to derive IPT).

This makes OKLab essentially "IPT with better-fitted matrices and correct lightness/chroma prediction matching CAM16."

### 1.2 Coordinate System and Geometry

A colour in OKLab is represented as **(L, a, b)**:

| Component | Meaning | Typical sRGB range |
|-----------|---------|-------------------|
| **L** | Perceptual lightness | 0 (black) → 1 (white) |
| **a** | Green (negative) ↔ Red (positive) | ≈ −0.23 → +0.28 |
| **b** | Blue (negative) ↔ Yellow (positive) | ≈ −0.31 → +0.20 |

CSS Color Level 4 assigns ±100% to ±0.4 for both a and b.

Neutral greys have a = 0, b = 0. Hue is undefined for achromatic colours.

### 1.3 Exact Conversion Matrices and Code

#### sRGB (gamma-encoded) → Linear sRGB

Before feeding values into OKLab, the sRGB gamma transfer function (IEC 61966-2-1) must be removed. From Ottosson's companion post ["It's Wrong"](https://bottosson.github.io/posts/colorwrong/):

```c
// sRGB encoded → linear light
float srgb_to_linear(float x) {
    if (x >= 0.04045)
        return pow((x + 0.055) / 1.055, 2.4);
    else
        return x / 12.92;
}

// linear light → sRGB encoded
float linear_to_srgb(float x) {
    if (x >= 0.0031308)
        return 1.055 * pow(x, 1.0/2.4) - 0.055;
    else
        return 12.92 * x;
}
```

**Critical pitfall:** Operating on gamma-encoded 8-bit integers (0–255) without this linearisation step will produce systematically wrong OKLab values. In Aseprite Lua, pixel colour components are 0–255 integers; divide by 255 and apply `srgb_to_linear` before any OKLab arithmetic.

#### Linear sRGB → OKLab (direct combined matrix)

The full XYZ intermediate step is algebraically combined into a single linear sRGB→LMS matrix. From Ottosson's reference implementation (updated 2021-01-25 with higher-precision D65 values):

```c
struct Lab { float L; float a; float b; };
struct RGB { float r; float g; float b; };

Lab linear_srgb_to_oklab(RGB c) {
    // Step 1: Linear sRGB → approximate LMS (combined M1 * M_srgb_to_xyz)
    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
    float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
    float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;

    // Step 2: Cube-root nonlinearity
    float l_ = cbrtf(l);
    float m_ = cbrtf(m);
    float s_ = cbrtf(s);

    // Step 3: M2 matrix → Lab
    return {
        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_,
    };
}
```

#### OKLab → Linear sRGB (inverse)

```c
RGB oklab_to_linear_srgb(Lab c) {
    // Step 1: M2_inverse
    float l_ = c.L + 0.3963377774f * c.a + 0.2158037573f * c.b;
    float m_ = c.L - 0.1055613458f * c.a - 0.0638541728f * c.b;
    float s_ = c.L - 0.0894841775f * c.a - 1.2914855480f * c.b;

    // Step 2: Cube (inverse of cube root)
    float l = l_*l_*l_;
    float m = m_*m_*m_;
    float s = s_*s_*s_;

    // Step 3: M1_inverse * M_xyz_to_srgb
    return {
        +4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s,
    };
}
```

> **Note from Ottosson:** "The matrices were updated 2021-01-25. The new matrices have been derived using a higher precision sRGB matrix and with exactly matching D65 values. The old matrices are available [here] for reference. The values only differ after the first three decimals."

#### XYZ → OKLab (via explicit matrices M1 and M2)

For use cases starting from CIE XYZ (D65, Y=1 for white):

```
M1 = | +0.8189330101  +0.3618667424  −0.1288597137 |
     | +0.0329845436  +0.9293118715  +0.0361456387 |
     | +0.0482003018  +0.2643662691  +0.6338517070 |

M2 = | +0.2104542553  +0.7936177850  −0.0040720468 |
     | +1.9779984951  −2.4285922050  +0.4505937099 |
     | +0.0259040371  +0.7827717662  −0.8086757660 |
```

Conversion pipeline: `XYZ → (lms) = M1·XYZ → (l',m',s') = cbrt(lms) → (L,a,b) = M2·(l',m',s')`

#### Verification Test Vectors

From Ottosson's post (XYZ → OKLab, rounded to 3 decimals):

| X     | Y     | Z     | L     | a      | b      |
|-------|-------|-------|-------|--------|--------|
| 0.950 | 1.000 | 1.089 | 1.000 | 0.000  | 0.000  |
| 1.000 | 0.000 | 0.000 | 0.450 | 1.236  | −0.019 |
| 0.000 | 1.000 | 0.000 | 0.922 | −0.671 | 0.263  |
| 0.000 | 0.000 | 1.000 | 0.153 | −1.415 | −0.449 |

### 1.4 OKLCh: The Cylindrical Form

OKLCh is the polar-coordinate representation of OKLab. The Wikipedia article on the [Oklab color space](https://en.wikipedia.org/wiki/Oklab_color_space) confirms:

```
C = sqrt(a² + b²)          -- chroma (unsigned distance from achromatic axis)
h = atan2(b, a)            -- hue angle in radians (convert to degrees: × 180/π)
```

Inverse:
```
a = C · cos(h)
b = C · sin(h)
```

| Component | Meaning | Notes |
|-----------|---------|-------|
| **L** | Perceptual lightness | 0–1 |
| **C** | Chroma | ≥ 0, sRGB max ≈ 0.32 |
| **h** | Hue angle | 0–360° or 0–2π rad |

**OKLCh hue angles for key colours (approximate, sRGB primaries):**
- Red: ~29°
- Yellow: ~110°
- Green: ~142°
- Cyan: ~195°
- Blue: ~264°
- Magenta: ~329°

As noted by Evil Martians ([OKLCH in CSS](https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl)):
> "OKLCH doesn't deform the space; it shows the real color space with all its complexity. Not all number combinations in OKLCH generate visible colors."

**For palette-compression hue-shifting:** OKLCh is the preferred working space because hue angle `h` is a clean rotational parameter. Shifting `h` by ±N degrees rotates the colour wheel perceptually uniformly (unlike HSL/HSV hue, which is non-linear). Adjusting `C` changes saturation without affecting lightness. Adjusting `L` changes brightness without affecting hue.

### 1.5 Comparison with Other Colour Spaces

From the error table published in Ottosson's OKLab post (lower = better; CAM16 is the reference ground truth):

| Space | L RMS | C RMS | H RMS | L 95th % | C 95th % | H 95th % |
|-------|-------|-------|-------|----------|----------|----------|
| **OKLab** | **0.20** | **0.81** | 0.49 | **0.44** | **1.78** | 1.06 |
| CIELAB | 1.70 | 1.84 | 0.69 | 3.16 | 3.96 | 1.56 |
| CIELUV | 1.72 | 2.32 | 0.68 | 3.23 | 5.03 | 1.51 |
| OSA-UCS | 2.05 | 1.28 | 0.49 | 4.04 | 2.73 | 1.08 |
| IPT | 4.92 | 2.18 | **0.48** | 9.89 | 4.64 | **1.02** |
| JzAzBz | 2.38 | 1.79 | **0.43** | 4.55 | 3.77 | **0.92** |
| HSV | 11.59 | 3.38 | 1.10 | 23.17 | 7.51 | 2.42 |
| CAM16-UCS | 0.00 | 0.00 | 0.59 | 0.00 | 0.00 | 1.31 |

**Key takeaways for our use case:**

- **OKLab wins decisively on lightness (L) and chroma (C) prediction.** L error is 8.5× lower than CIELAB. This is the most important quality for palette reduction that preserves perceived contrast.
- **Hue uniformity:** OKLab is good (0.49 RMS), nearly tied with OSA-UCS and slightly behind IPT/JzAzBz. The infamous CIELAB blue-region hue shift is eliminated.
- **Computational cost:** OKLab is extremely cheap — two 3×3 matrix multiplies + three cube-roots, fully algebraically invertible. No iterative solvers, no lookup tables required. JzAzBz and ICtCp require the PQ (ST 2084) transfer function, which is more expensive. CIECAM02/CAM16 requires ~30+ operations including branching and chromatic adaptation.
- **vs CIELAB:** CIELAB has severe hue-shift problems in blue/violet (270–330°), exactly the range most important to retro/pixel art. OKLab corrects this. CIELAB's L* axis is also less accurate than OKLab's L.
- **vs HSLuv:** HSLuv (built on CIELuv) maps sRGB to a cylinder, so maximum saturation is gamut-relative. It has good lightness but poor hue uniformity for blues/purples due to the Abney effect. OKLab has better hue linearity for the full gamut.
- **vs JzAzBz:** JzAzBz is designed for HDR and has scale/exposure dependence (Y=100 white vs Y=1). For SDR pixel art this dependence is a liability. OKLab is scale-invariant.
- **vs CIECAM02/CAM16:** These are the most perceptually accurate models but require absolute luminance, background adaptation, and viewing conditions as inputs — none of which are known in a palette tool context. OKLab was deliberately designed to sidestep this requirement.
- **OKLab limitation:** Not perfectly perceptually uniform (no colour space is — colour perception is non-Euclidean). For very large colour differences (ΔE > ~10 CIELAB units), the Euclidean OKLab distance becomes less reliable. For small palette differences in pixel art (typically within a few perceptual steps), it is excellent.

### 1.6 Known Pitfalls and Gotchas

#### 1. sRGB Gamma (Transfer Function)

**The single most common implementation error.** sRGB values (bytes 0–255, or floats 0.0–1.0) are gamma-encoded. OKLab requires *linear* light values. If you skip linearisation:
- All your L values will be too high (the gamma curve is brighter than linear).
- The L dimension becomes non-uniform.
- Colour difference calculations will be wrong.

**Fix:** Always apply `srgb_to_linear(x/255)` before converting to OKLab, and `linear_to_srgb(x)*255` after converting back.

In Lua (Aseprite), this looks like:
```lua
local function srgb_to_linear(c)
    c = c / 255.0
    if c >= 0.04045 then
        return ((c + 0.055) / 1.055) ^ 2.4
    else
        return c / 12.92
    end
end

local function linear_to_srgb(c)
    if c >= 0.0031308 then
        c = 1.055 * (c ^ (1.0/2.4)) - 0.055
    else
        c = 12.92 * c
    end
    return math.floor(c * 255 + 0.5)
end
```

#### 2. Out-of-Gamut Handling

When mapping OKLab values back to sRGB, it is possible to get linear sRGB values outside [0, 1]. This happens:
- When manipulating C (chroma) upward beyond the gamut boundary.
- When interpolating between two in-gamut colours in OKLab (some intermediate colours may briefly exceed the gamut).
- After k-means centroid averaging (centroids may fall slightly outside sRGB).

Naïve RGB clamping (clamp each channel to [0,1]) distorts hue dramatically.

#### 3. Chroma Clipping in OKLCh

When a colour with high C and a given h falls outside sRGB, reducing C while keeping L and h constant is the safest approach (chroma clipping, also called "hue-preserving gamut reduction"). This is the strategy Ottosson recommends as a starting point in the gamut clipping article.

For palette compression, any k-means centroid that falls outside sRGB should be projected back to the gamut boundary using the hue-preserving method before being used as a palette entry.

#### 4. Achromatic Hue Singularity

When C ≈ 0, the hue angle `h = atan2(b, a)` is numerically undefined (both a and b ≈ 0). This creates a singularity in OKLCh space. When computing distances in OKLCh, use the Euclidean OKLab distance (L, a, b) instead of the cylindrical (L, C, ΔH) form for near-grey colours. Alternatively, weight the hue term by C to smoothly suppress it as colours approach grey.

#### 5. Cube Root of Negative Numbers

The cube root is applied to l, m, s values that should always be non-negative for in-gamut colours. For out-of-gamut inputs, l/m/s can be negative. Use a sign-preserving cube root: `cbrt(x) = sign(x) * |x|^(1/3)`.

### 1.7 Gamut Mapping and Clipping in OKLab

From Ottosson's follow-up article *"Gamut Clipping"* ([https://bottosson.github.io/posts/gamutclipping/](https://bottosson.github.io/posts/gamutclipping/)):

The general problem: given a colour (L, C, h°) in OKLCh that is outside sRGB, find the nearest in-gamut colour.

**Strategy — projection approach:**
> "Work in a perceptual color space. Keep hue constant, only change lightness and chroma. Only project color along straight lines in the perceptual color space."

**Finding the gamut boundary (hue slice):**
The sRGB gamut, viewed in an OKLab L–C slice at constant hue, approximates a triangle with corners at (L=0, C=0), (L=1, C=0), and a cusp point (L_cusp, C_cusp) that depends on hue angle.

Ottosson provides a numerical approximation + one step of Halley's method to find (L_cusp, C_cusp) efficiently.

**Gamut clipping methods compared:**

| Method | Description | Quality |
|--------|-------------|---------|
| RGB clamp | Clamp R,G,B to [0,1] | Poor — severe hue distortion |
| Chroma compress | Keep L, reduce C to gamut edge | Good for most colours |
| Project toward L=0.5 | Straight line to mid-grey | Good overall |
| Project toward L=L_cusp | Straight line toward hue cusp | Good, hue-specific |
| **Adaptive L0 (recommended)** | Blends chroma compress and single-point; parameter α controls trade-off | Best overall |

**Ottosson's recommendation:**
> "Personally, of the methods evaluated here, I think a good default choice would be adaptive L0 with α=0.05, but in specific cases other methods and α values can definitely perform better."

For palette compression, the **chroma clipping** method (reduce C, keep L and h) is usually sufficient and simplest to implement, as we are not aggressively boosting colours — we are averaging them.

---

## 2. Perceptual Distance Metrics

### 2.1 Delta-E Variants

All ΔE formulas are designed so ΔE = 1.0 approximately equals a Just Noticeable Difference (JND). ΔE(CIE76) recalibrated to ΔE*_ab ≈ 2.3 for JND.

#### CIE76 (ΔE*_ab)

The simplest: Euclidean distance in CIELAB.

```
ΔE_76 = sqrt( (L2-L1)² + (a2-a1)² + (b2-b1)² )
```

- **Pros:** Simple, fast, the foundation of all subsequent formulas.
- **Cons:** CIELAB is not perceptually uniform, especially in saturated blues/cyans and high-chroma yellows. The formula overestimates differences in saturated regions. JND threshold is ≈ 2.3, not 1.0.

#### CIE94 (ΔE*_94)

Adds hue-dependent weighting factors to correct for CIELAB's non-uniformities:

```
ΔE_94 = sqrt( (ΔL/kL*SL)² + (ΔC/kC*SC)² + (ΔH/kH*SH)² )
where SL=1, SC=1+K1*C1, SH=1+K2*C1
Graphic arts: kL=1, K1=0.045, K2=0.015
```

- **Pros:** Better than CIE76 for high-chroma colours.
- **Cons:** Asymmetric (reference colour matters), still based on CIELAB, doesn't handle blue region well.

#### CIEDE2000 (ΔE*_00)

The current CIE standard. Adds five correction terms to CIE94:

```
ΔE_00 = sqrt( (ΔL'/kL*SL)² + (ΔC'/kC*SC)² + (ΔH'/kH*SH)² + RT*(ΔC'/SC)*(ΔH'/SH) )
```

Corrections include:
- **Hue rotation term RT**: specifically compensates for the blue region (h ≈ 275°).
- **Neutral colour compensation** (primed a' values).
- **Position-dependent lightness, chroma, hue scaling** (SL, SC, SH).
- The T parameter: `T = 1 − 0.17cos(h̄'−30°) + 0.24cos(2h̄') + 0.32cos(3h̄'+6°) − 0.20cos(4h̄'−63°)`

- **Pros:** Best standardised ΔE for SDR sRGB colours. Used in printing, textiles, automotive.
- **Cons:** Complex (~20 intermediate calculations), mathematically discontinuous at hue ≈ 180° apart (up to 4%), expensive for millions of comparisons. Not designed for OKLab (it operates in CIELAB L*a*b*).

#### HyAB (Hybrid ΔE, CIELAB)

A hybrid using L1 norm for lightness and L2 for chroma:
```
ΔE_HyAB = sqrt( (a2-a1)² + (b2-b1)² ) + |L2-L1|
```

Research by Abasi et al. (2020) showed HyAB outperforms both Euclidean and CIEDE2000 for *large* colour differences (>10 CIELAB units). Interesting for palette compression where distances can be large.

#### OK-Distance (Euclidean OKLab)

Not a formal standard, but effectively what OKLab is designed for:

```lua
local function oklab_distance_sq(a, b)
    local dL = a.L - b.L
    local da = a.a - b.a
    local db = a.b - b.b
    return dL*dL + da*da + db*db
end
```

From Wikipedia on color difference:
> "Color spaces that improve on [CIELAB non-uniformity] include CAM02-UCS, CAM16-UCS, and Jzazbz." OKLab is in the same category.

From Ottosson's derivation: OKLab was fitted to minimise errors predicted by CIEDE2000 on the test datasets, so its Euclidean distance is implicitly a good approximation of CIEDE2000 for the sRGB gamut under normal viewing conditions.

### 2.2 Euclidean Distance in OKLab as a ΔE Approximation

**Why it works well for our use case:**

1. OKLab was derived by optimising against CAM16 lightness/chroma data and Ebner–Fairchild hue data, both of which are used to calibrate CIEDE2000. As Ottosson states: "The aa and bb plane is scaled so that around 50% gray the ratio of color differences along the lightness axis and the aa and bb plane is the same as the ratio for color differences predicted by CIEDE2000."

2. Raph Levien's 2021 review ([raphlinus.github.io](https://raphlinus.github.io/color/2021/01/18/oklab-critique.html)) confirms OKLab's lightness prediction is superior to IPT and comparable to CIELAB for lightness, while its hue linearity is far better.

3. For pixel-art palettes (typically 4–256 colours within sRGB), the colour differences we compare tend to be small-to-medium (< 10 CIELAB units). In this range, Euclidean OKLab distance is an excellent ΔE proxy.

**Where it breaks down:**

- **Very large colour differences** (opposite sides of the gamut): Non-Euclidean nature of perception means any Euclidean metric underestimates hue differences and overestimates lightness differences at extremes.
- **Near-grey colours with different hues**: At low chroma, the hue angle becomes ill-defined; Euclidean distance handles this gracefully (a and b both near zero, hue has negligible weight automatically).
- **HDR or wide-gamut content** (beyond sRGB): OKLab's scale-invariance assumption breaks down at extreme brightnesses; JzAzBz or ICtCp are better choices there.

**For palette compression, the recommendation is:**
Use `sqrt((ΔL)² + (Δa)² + (Δb)²)` in OKLab. Skip CIEDE2000 — the extra accuracy does not justify the cost for this application, and CIEDE2000 is designed for CIELAB space anyway.

### 2.3 Weighting Lightness vs Chroma vs Hue

For **aesthetic** palette reduction (preserving visually distinct colours rather than minimising raw perceptual error), the following weighting strategy is well-motivated:

#### Standard Equal Weighting (baseline)
```
d² = (ΔL)² + (Δa)² + (Δb)²
```
Works well for most cases.

#### Lightness-Weighted
Pixel art contrast often depends primarily on lightness difference (dark/light ramps). Boost L weight:
```lua
d² = wL*(ΔL)² + (Δa)² + (Δb)²
-- Typical: wL = 2.0  (lightness twice as important)
```
This preserves the perceived contrast structure of ramps.

#### OKLCh Cylindrical Weighting
In cylindrical form, hue differences between saturated and desaturated colours can be misleading. Weight hue by chroma:
```lua
-- In OKLCh:
local avgC = (C1 + C2) / 2
local dH_sq = 2 * C1 * C2 * (1 - math.cos(h2 - h1))   -- chord formula
d² = wL*(ΔL)² + wC*(ΔC)² + wH*avgC*dH_sq
```

#### Practical Recommendations for Pixel Art
- **For palette merging/compression:** Use standard Euclidean OKLab with mild lightness boost (wL ≈ 1.5–2.0).
- **For finding nearest palette colour (remapping):** Standard equal-weight Euclidean is fine.
- **For hue-shift detection (preserving intentional hue variety):** Use OKLCh with explicit hue component; flag colours as "hue-distinct" if |Δh| > 15° at C > 0.05.

---

## 3. Palette Quantisation Algorithms in Perceptual Spaces

### 3.1 Classic Algorithms

#### Median Cut (Heckbert 1979)

The most historically popular algorithm. From [Wikipedia: Color quantization](https://en.wikipedia.org/wiki/Color_quantization):
> "The most popular algorithm by far for color quantization, invented by Paul Heckbert in 1979, is the median cut algorithm. Many variations on this scheme are in use."

**Standard algorithm (in RGB):**
1. Put all pixel colours in one bucket.
2. Find the colour channel with the greatest range in the bucket.
3. Sort by that channel; split at the median.
4. Repeat until you have *k* buckets.
5. Average colours within each bucket → palette entry.

**Modified for perceptual spaces:** Replace RGB axes with OKLab L, a, b axes. Split along the axis with greatest *perceptual* range.

From [Wikipedia: Median cut](https://en.wikipedia.org/wiki/Median_cut):
> "Median cut is typically used for color quantization. For example, to reduce a 64k-colour image to 256 colours, median cut is used to find 256 colours that match the original data well."

**Strengths:** Fast O(n log n), deterministic, works well for images with broad colour distributions.
**Weaknesses:** Tends to over-represent majority colours; can merge perceptually distinct but low-frequency colours; does not account for pixel count weighting in its basic form.

**Leptonica's Modified Median Cut** ("Median Cut with Variance Minimization"):
The [Leptonica library](http://www.leptonica.org/papers/mediancut.pdf) paper (Bloomberg, available at `http://www.leptonica.com/papers/mediancut.pdf`) extends median cut with:
- Population-weighted splitting (split where pixel count is balanced, not just at the median of the value range).
- Variance-based bucket selection (split the bucket with highest variance, not the largest).
This gives significantly better results for images with varied colour distributions.

#### Octree Quantisation (Gervautz & Purgathofer; Bloomberg/Xerox PARC)

Builds an octree in the RGB cube (or LAB cube), merging leaf nodes until the desired number of colours remains.

**Strengths:** Single-pass, memory-efficient, fast.
**Weaknesses:** Quality below k-means or median cut; tends to lose subtle colour distinctions.

#### k-Means Clustering

From [Wikipedia: k-means clustering](https://en.wikipedia.org/wiki/K-means_clustering):
> "k-means clustering aims to partition n observations into k clusters so as to minimize the within-cluster sum of squares (WCSS)."

```
Algorithm (Lloyd's/Forgy):
1. Choose k initial centroids.
2. Assign each colour to nearest centroid (Voronoi partition).
3. Recompute centroids as means of assigned colours.
4. Repeat 2–3 until convergence (assignments unchanged).
```

This is NP-hard to solve globally, but the heuristic converges quickly to a local optimum.

**In perceptual space (OKLab):** Running k-means in OKLab space produces palette centroids that minimise perceptual error (total squared OKLab distance from each pixel to its palette colour). This is far superior to k-means in RGB or HSV.

From the [Color quantization Wikipedia article](https://en.wikipedia.org/wiki/Color_quantization):
> "In 2011, M. Emre Celebi reinvestigated the performance of k-means as a color quantizer. He demonstrated that an efficient implementation of k-means outperforms a large number of color quantization methods."

**Pixel-frequency weighting:** Rather than storing N_pixels individual colour points, store unique-colour histogram entries `(color, count)` and treat `count` as a weight in centroid computation:
```
centroid = sum(color_i * count_i) / sum(count_i)  for all i in cluster
```
This reduces computation from O(pixels) to O(unique_colours), which for small pixel-art sprites can be dramatically faster.

**Strengths:** Best average quality; adaptable; perceptually optimal in the chosen space.
**Weaknesses:** Non-deterministic (depends on initialisation); can converge to poor local optima; multiple restarts may be needed; O(k × unique_colours × iterations).

#### Wu's Colour Quantiser (Greedy Orthogonal Bipartition)

Published by Xiaolin Wu in 1992 ("Efficient Statistical Computations for Optimal Color Quantization", *Graphics Gems II*). Wu's quantiser uses a moment-based approach on a 3D histogram to find cuts that minimise within-cluster variance, producing results comparable to k-means but in a single deterministic pass.

**Strengths:** Deterministic, fast, excellent quality — often used as a reference implementation.
**Weaknesses:** Fixed to the RGB (or other 3-channel) cube; adapting to OKLab requires rebuilding the moment tables in OKLab space.

#### NeuQuant (Kohonen Neural Network)

From [Wikipedia: Color quantization](https://en.wikipedia.org/wiki/Color_quantization):
> "The high-quality but slow NeuQuant algorithm reduces images to 256 colors by training a Kohonen neural network which self-organises through learning to match the distribution of colours in an input image."

**Strengths:** Very high quality, especially for images with gradients.
**Weaknesses:** Slow; not easily adapted to perceptual spaces; overkill for small pixel-art palettes.

#### Spatial Colour Quantisation (Puzicha, Held, Ketterer, Buhmann, Fellner — University of Bonn)

From [Wikipedia: Color quantization](https://en.wikipedia.org/wiki/Color_quantization):
> "conceived by Puzicha, Held, Ketterer, Buhmann, and Fellner of the University of Bonn, which combines dithering with palette generation and a simplified model of human perception to produce visually impressive results even for very small numbers of colors. It does not treat palette selection strictly as a clustering problem, in that the colors of nearby pixels in the original image also affect the color of a pixel."

This is the only standard algorithm that integrates spatial context (neighbouring pixels) into palette selection — making it potentially relevant for pixel art where spatial structure matters.
See sample images at: `https://web.archive.org/web/20160426135306/www.cs.berkeley.edu/~dcoetzee/downloads/scolorq/#sampleimages`

### 3.2 Implementations in CIELab / OKLab

| Library / Tool | Language | Colour Space | Algorithm | Notes |
|----------------|----------|-------------|-----------|-------|
| [colour-science/colour](https://github.com/colour-science/colour) | Python | OKLab (native) | Various | Recommended by Ottosson himself |
| [libimagequant](https://github.com/ImageOptim/libimagequant) | C/Rust | Lab-like (internal) | Modified k-means | Used by pngquant; very high quality |
| [scolorq](https://github.com/dcoetzee/scolorq) | C++ | RGB perceptual weights | Spatial CQ | Reference implementation of Puzicha et al. |
| [pngquant](https://github.com/kornelski/pngquant) | C/Rust | Internal Lab-like | k-means (libimagequant) | Best-in-class PNG quantiser |
| [Leptonica](http://www.leptonica.org) | C | RGB | Modified Median Cut | Well-documented; paper available |

For Lua/Aseprite, none of these are directly importable. We must implement in pure Lua. The recommended approach:
1. Convert all unique palette colours to OKLab.
2. Run weighted k-means in OKLab space (weights = pixel counts).
3. Project any out-of-gamut centroids back to sRGB boundary.
4. Convert centroids back to sRGB.

### 3.3 Weighted k-Means with Pixel-Frequency Weights

**Algorithm pseudocode (OKLab space):**

```
-- Input: palette_colors[] (unique sRGB colours), counts[] (pixel frequencies)
-- Target: k colours

1. Convert all palette_colors to OKLab: oklab_colors[]

2. Initialize k centroids (see §3.4)

3. repeat
     -- Assignment step
     for each (color, count) in (oklab_colors, counts):
         nearest_centroid = argmin_j(oklab_distance_sq(color, centroid[j]))
         cluster[nearest_centroid].add(color, weight=count)
     
     -- Update step (weighted centroid)
     for j = 1 to k:
         if cluster[j] is non-empty:
             centroid[j].L = sum(color.L * weight) / sum(weight)  for color in cluster[j]
             centroid[j].a = sum(color.a * weight) / sum(weight)
             centroid[j].b = sum(color.b * weight) / sum(weight)
   
   until centroids unchanged (or max_iterations reached)

4. For each centroid, convert OKLab → linear sRGB → gamma-encoded sRGB
5. Clamp any out-of-gamut values using hue-preserving chroma reduction
6. Return k palette colours
```

**Convergence criterion:** Either no assignment changes between iterations, or the maximum centroid movement (in OKLab Euclidean distance) is below a threshold (e.g., 0.001).

**Iteration limit:** 50–100 iterations is usually sufficient for small palettes (k ≤ 32).

### 3.4 k-Means++ Seeding

Standard random initialisation often leads to poor local optima. **k-means++** (Arthur & Vassilvitskii, 2007) gives dramatically better starting centroids:

```
Algorithm:
1. Choose first centroid uniformly at random from the colour set.
2. For each remaining centroid i = 2..k:
   a. Compute d(x)² = min squared OKLab distance from each colour x to the nearest already-chosen centroid.
   b. Weight the probability of each colour being chosen proportional to d(x)².
   c. Choose next centroid by weighted random sample.
3. Proceed with standard k-means.
```

From [Wikipedia: k-means clustering](https://en.wikipedia.org/wiki/K-means_clustering):
> "A comprehensive study by Celebi et al. found that popular initialization methods such as Forgy, Random Partition, and Maximin often perform poorly, whereas ... k-means++ performs 'generally well'."

**For pixel art:** Because palettes are small (often 8–64 entries to reduce to 4–32), k-means++ seeding is fast and strongly recommended. Weight the initial selection by pixel frequency (highly-used colours should be more likely to become initial centroids).

---

## 4. Pixel-Art Specific Considerations

### 4.1 Why Pixel Art Resists Generic Quantisation

Generic colour quantisation (median cut, octree, generic k-means) is designed for photographic content where:
- Millions of unique colours exist.
- Colour distributions are broad and continuous.
- Nearby pixels in the image have similar colours (natural gradients).
- Any individual pixel is perceptually unimportant.

Pixel art inverts almost all these assumptions:

1. **Small unique colour counts:** A typical pixel art sprite may use only 8–64 distinct colours. The entire "palette" may already fit in k clusters with no simplification needed.

2. **Intentional ramp structure:** Pixel art colours are arranged in *ramps* — deliberate sequences of increasing lightness/saturation for a given hue, used to suggest 3D shading. These ramps have precise perceptual relationships. A generic quantiser that merges two adjacent ramp steps destroys this structure, making the result look "flat" or "airbrushed".

3. **Intentional dithering:** Many pixel artists use 1:1 checkerboard or ordered dithering patterns to simulate intermediate colours. These require the two participating colours to remain distinct. If quantisation merges them, the dithering pattern collapses to a solid area.

4. **Intentional hue shifting in ramps:** A classic retro technique involves having the shadow end of a ramp shift toward purple/blue (cool), and the highlight end shift toward yellow/orange (warm). This mimics subsurface scattering and atmospheric colour. Any quantisation that operates purely on L distance (conflating cool shadow and warm highlight if they have similar lightness) destroys this intentional hue variation.

5. **Hard edge preservation:** Pixel art uses hard 1-pixel edges between colour regions. Anti-aliasing artefacts — semi-transparent pixels or colours that blend two regions — are typically absent or added very deliberately ("anti-aliasing" in traditional pixel art means AA pixels are intentionally placed, not a side-effect of the renderer).

6. **Small sprite/tile sizes:** A 16×16 sprite has only 256 pixels total. The "most frequent colour" in such a sprite may appear only a handful of times. Frequency-weighted quantisation can catastrophically under-represent important outline or highlight colours that appear just once or twice.

**Implication for compression strategy:** Rather than treating palette compression as a pure clustering problem, it should incorporate *structural constraints*:
- Identify ramps (sequences of colours with similar hue, monotonically varying L/C).
- Within a ramp, merge only adjacent entries that are perceptually too close (ΔE < threshold in OKLab).
- Between different hues, always preserve the distinction (never merge colours with |Δh| > 15° when C > 0.05).

### 4.2 Preserving Hard Edges and Avoiding Antialiasing Artefacts

**Hard edges in pixel art** are pairs of adjacent pixels whose colours have a large OKLab distance (ΔE > ~15 in CIELAB units, or roughly OKLab distance > ~0.15). These transitions define the character's outline and form.

**Risk during quantisation:** If two colours A and B appear adjacent in the image and both get mapped to the same cluster centroid C, the edge between them disappears. The result looks "blurry" even though no spatial filtering occurred — it's a *colour space* artefact.

**Mitigation strategies:**
1. **Edge-aware constraint:** Before merging two palette entries, check if they appear adjacent in the sprite. If yes, penalise (or forbid) their merger unless ΔE is very small.
2. **Threshold-based merging:** Only merge entries whose pairwise OKLab distance is below a strict threshold (e.g., OKLab distance < 0.05, roughly ΔE_00 < 2).
3. **Ramp structure preservation:** Identify ramps and only allow merging within a ramp (never across different hue families).

**Anti-aliasing artefacts** can appear during re-palette if:
- The mapping from original palette to compressed palette is done by nearest-colour in RGB rather than OKLab — some colours jump to perceptually distant neighbours.
- The compressed palette has poor coverage of the original colour space, causing large "jumps" in the Voronoi partition.

**Fix:** Always do palette mapping (original colour → nearest compressed colour) in OKLab space.

### 4.3 Transparent and Partially-Transparent Pixels

Aseprite supports RGBA images with full transparency channels. Palette compression must handle:

1. **Fully transparent pixels (alpha = 0):** These have undefined colour (the RGB components are irrelevant). They must **not** be included in the colour distribution analysis. Including them would skew the distribution toward whatever value the RGB components happen to have (often 0,0,0 or 255,255,255 depending on the editor).

2. **Palette index 0 (transparent index):** In indexed colour mode, palette index 0 is conventionally the transparent colour. The palette compression must reserve index 0 for this purpose and must not use it for a real colour.

3. **Partially transparent pixels (0 < alpha < 255):** These are problematic for palette compression:
   - Option A: **Ignore alpha, compress only colours.** After remapping, partially-transparent pixels keep their alpha but get the nearest opaque colour. This is simplest.
   - Option B: **Include alpha as a 4th dimension in OKLab distance.** Use (L, a, b, α) as a 4D point. This preserves the alpha structure but may cause issues if alpha varies smoothly (creating clusters with mixed alpha values).
   - Option C: **Pre-multiply alpha before converting to OKLab.** This is physically correct (pre-multiplied alpha represents the actual light contribution). Convert `(R, G, B, A)` → `(R*A/255, G*A/255, B*A/255)` before linearisation and OKLab conversion.
   - **Recommendation:** For pixel art, use Option A (ignore alpha in clustering, preserve per-pixel alpha in remapping). Partially-transparent pixels in pixel art are rare and intentional; treat them as their full-colour value for palette purposes.

4. **Counting:** Only count pixels with alpha ≥ some threshold (e.g., alpha ≥ 128) as "present" for frequency-weighted clustering. Pixels below the threshold are treated as transparent and excluded.

---

## 5. Implementation Guidance for Lua/Aseprite

### Recommended Algorithm Stack

```
1. Collect all colours from sprite (iterate pixels, skip alpha=0)
2. Build frequency histogram: { [r*65536 + g*256 + b] = count }
3. Convert each unique colour to OKLab (linearise sRGB first)
4. Run k-means++ in OKLab with frequency weights
5. Convert centroids back to sRGB (with gamut clipping if needed)
6. Build mapping: original colour → nearest centroid (in OKLab)
7. Apply mapping to sprite pixels
8. Update Aseprite palette with compressed entries
```

### Lua Cube Root

Lua 5.1 (used in Aseprite) does not have `math.cbrt`. Use:
```lua
local function cbrt(x)
    if x >= 0 then
        return x ^ (1/3)
    else
        return -((-x) ^ (1/3))
    end
end
```

### OKLab Conversion in Lua

```lua
local function rgb_to_oklab(r, g, b)
    -- r, g, b are 0-255 integers
    local function lin(c)
        c = c / 255.0
        if c >= 0.04045 then return ((c + 0.055) / 1.055) ^ 2.4
        else return c / 12.92 end
    end
    local rl, gl, bl = lin(r), lin(g), lin(b)
    
    local l = 0.4122214708*rl + 0.5363325363*gl + 0.0514459929*bl
    local m = 0.2119034982*rl + 0.6806995451*gl + 0.1073969566*bl
    local s = 0.0883024619*rl + 0.2817188376*gl + 0.6299787005*bl
    
    local l_ = cbrt(l)
    local m_ = cbrt(m)
    local s_ = cbrt(s)
    
    return {
        L = 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        a = 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        b = 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
    }
end

local function oklab_to_rgb(L, a, b)
    local l_ = L + 0.3963377774*a + 0.2158037573*b
    local m_ = L - 0.1055613458*a - 0.0638541728*b
    local s_ = L - 0.0894841775*a - 1.2914855480*b
    
    local l = l_*l_*l_
    local m = m_*m_*m_
    local s = s_*s_*s_
    
    local rl =  4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    local gl = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    local bl = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s
    
    -- Clamp to [0,1] and apply sRGB gamma
    local function gamma(c)
        c = math.max(0, math.min(1, c))
        if c >= 0.0031308 then return 1.055 * c^(1/2.4) - 0.055
        else return 12.92 * c end
    end
    
    return
        math.floor(gamma(rl) * 255 + 0.5),
        math.floor(gamma(gl) * 255 + 0.5),
        math.floor(gamma(bl) * 255 + 0.5)
end
```

### Performance Notes

- Aseprite's Lua environment is single-threaded; for sprites with large unique colour counts, pre-compute all OKLab values once.
- For palettes already down to ≤ 256 entries, the k-means inner loop runs on at most 256 points — trivially fast even with 100 iterations.
- Avoid recomputing `cbrt` in tight loops; cache OKLab values.

---

## 6. Citations

| # | URL | Description |
|---|-----|-------------|
| 1 | https://bottosson.github.io/posts/oklab/ | Ottosson, B. (2020). *"A perceptual color space for image processing."* Original OKLab blog post with conversion matrices, derivation methodology, and comparison tables. Primary source. |
| 2 | https://bottosson.github.io/posts/gamutclipping/ | Ottosson, B. (2021). *"Gamut Clipping."* Describes five methods for mapping out-of-gamut OKLab colours back into sRGB, including the recommended adaptive L0 method (α=0.05). |
| 3 | https://bottosson.github.io/posts/colorwrong/ | Ottosson, B. (2020). *"It's Wrong."* Explains the sRGB gamma transfer function problem, provides C pseudocode for sRGB↔linear conversion. |
| 4 | https://bottosson.github.io/posts/colorpicker/ | Ottosson, B. (2021). *"Two new color spaces for color picking."* Introduces Okhsl/Okhsv; comprehensive comparison of HSV, HSL, HSLuv, CIELab, and OKLab for perceptual colour picking. |
| 5 | https://en.wikipedia.org/wiki/Oklab_color_space | Wikipedia: *Oklab color space.* Summary of OKLab/OKLCh coordinates, conversion formulas, CSS Level 4 standardisation status. |
| 6 | https://en.wikipedia.org/wiki/Color_difference | Wikipedia: *Color difference.* Comprehensive reference for CIE76, CIE94, CIEDE2000, CMC, HyAB, and ITP delta-E formulas with full equations. |
| 7 | https://en.wikipedia.org/wiki/Color_quantization | Wikipedia: *Color quantization.* Overview of median cut, octree, k-means, NeuQuant, and spatial colour quantisation; historical context and application notes. |
| 8 | https://en.wikipedia.org/wiki/Median_cut | Wikipedia: *Median cut.* Algorithm description and links to Leptonica's modified median cut paper. |
| 9 | https://en.wikipedia.org/wiki/K-means_clustering | Wikipedia: *k-means clustering.* Full algorithm, pseudocode, initialisation methods (k-means++), convergence properties. |
| 10 | https://en.wikipedia.org/wiki/Pixel_art | Wikipedia: *Pixel art.* Historical context, colour constraints, ramp structures, and characteristics of the medium. |
| 11 | https://raphlinus.github.io/color/2021/01/18/oklab-critique.html | Levien, R. (2021). *"An interactive review of Oklab."* Independent technical review; confirms OKLab's superior hue uniformity and lightness accuracy; discusses the IPT architecture and transfer function trade-offs. |
| 12 | https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl | Sitnik, A. & Turner, T. (2023). *"OKLCH in CSS: why we moved from RGB and HSL."* Practical guide to OKLCh; explains CSS Color 4 integration, P3 support, and comparison with HSL/LCH/RGB. |
| 13 | https://www.w3.org/TR/css-color-4/ | W3C CSS Color Module Level 4 (candidate recommendation). Formal standardisation of oklab() and oklch() in CSS with coordinate definitions. |

---

*Report prepared for the Aseprite Palette Compression with Hue Shifting Lua script project.*
*All conversion matrices and code are public domain / MIT licensed per Ottosson's explicit statement in the OKLab blog post.*
```

---

## Summary of Key Findings

Here is a concise summary of the most critical findings for the palette-compression script:

### Critical Conversions (Verbatim Coefficients)
The **linear sRGB → OKLab** matrix (updated 2021-01-25, highest precision):
- LMS step: `l = 0.4122214708r + 0.5363325363g + 0.0514459929b`; `m = 0.2119034982r + 0.6806995451g + 0.1073969566b`; `s = 0.0883024619r + 0.2817188376g + 0.6299787005b`
- Cube root: `l' = ∛l`, `m' = ∛m`, `s' = ∛s`
- Lab step: `L = 0.2104542553l' + 0.7936177850m' − 0.0040720468s'`; `a = 1.9779984951l' − 2.4285922050m' + 0.4505937099s'`; `b = 0.0259040371l' + 0.7827717662m' − 0.8086757660s'`

### Top Findings

1. **OKLab's L error is 8.5× lower than CIELAB** (0.20 vs 1.70 RMS) — critical for preserving perceived contrast in palette compression.
2. **Always linearise sRGB before converting** — the single most common implementation mistake that silently corrupts all perceptual calculations.
3. **Euclidean distance in OKLab is an excellent ΔE proxy** for the small-to-medium colour differences typical in pixel art palettes; skip the full CIEDE2000 formula.
4. **Weighted k-means++ in OKLab** is the recommended quantisation algorithm — frequency-weight by pixel count, seed with k-means++ for robust initialisation.
5. **Pixel art ramp structures must be detected and preserved** — generic quantisation will merge adjacent ramp steps and destroy intentional shading.
6. **Hue-shifting in ramps is perceptual, not aesthetic whimsy** — use OKLCh hue angle to detect intentional hue variation; colours with |Δh| > ~15° at C > 0.05 should never be merged.
7. **Out-of-gamut centroids must be handled** — after k-means averaging in OKLab, centroids may fall outside sRGB; use hue-preserving chroma reduction (reduce C, keep L and h) rather than RGB clamping.
8. **Transparent pixels (alpha=0) must be excluded** from the colour histogram entirely; reserve palette index 0 for transparency.

**Report target path:** `D:\Aseprite\Compress Palette with Hue Shifting\research\01-oklab-color-science.md