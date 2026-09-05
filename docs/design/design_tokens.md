# Guildford Vue — Design Tokens

**Version**: 1.0
**Date**: April 2026
**Source of truth**: This file. No ad-hoc values in components.

---

## Overview

Guildford Vue's design system is a small, disciplined set of tokens covering colour, typography, spacing, radius, elevation, motion, and breakpoints. The whole system is engineered to be:

- **Restrained** — three colours, two typefaces, one spacing scale
- **Accessible** — every primary pairing clears WCAG AA, most clear AAA
- **Functional** — every token serves a job; nothing is decorative-only
- **Implementable** — exposed as both Tailwind config and CSS custom properties

This document is the canonical reference. Engineering implementations (Tailwind config, CSS file) are derived from it.

---

## 1. Colour

### 1.1 Brand families

Three families, eleven stops each.

#### Teal — Primary brand

| Token | Hex | Use |
|-------|-----|-----|
| `teal-50` | `#F0FDFA` | Subtle success backgrounds |
| `teal-100` | `#CCFBF1` | "Available" badge background |
| `teal-200` | `#99F6E4` | Soft accents |
| `teal-300` | `#5EEAD4` | Eyebrow text on dark backgrounds |
| `teal-400` | `#2DD4BF` | Decorative accents on dark |
| `teal-500` | `#14B8A6` | Mid-tone interactive |
| `teal-600` | `#0D9488` | Primary button hover |
| **`teal-700`** | **`#0F766E`** | **Primary brand · CTAs · links** |
| `teal-800` | `#115E59` | Primary button active · hero surfaces |
| `teal-900` | `#134E4A` | Text on light teal backgrounds |
| `teal-950` | `#042F2E` | Hero backgrounds · deepest surfaces |

#### Orange — Accent & confirmation

| Token | Hex | Use |
|-------|-----|-----|
| `orange-50` | `#FFF7ED` | Warm-tinted card backgrounds |
| `orange-100` | `#FFEDD5` | "Limited" badge background |
| `orange-200` | `#FED7AA` | Soft accents |
| `orange-300` | `#FDBA74` | Hero italic emphasis on dark |
| `orange-400` | `#FB923C` | Mid-tone accents on dark |
| `orange-500` | `#F97316` | Decorative elements |
| `orange-600` | `#EA580C` | Accent button hover |
| **`orange-700`** | **`#C2410C`** | **Accent CTAs · section labels · confirmation pill** |
| `orange-800` | `#9A3412` | Accent button active · dark text on orange |
| `orange-900` | `#7C2D12` | Deepest accent surfaces |
| `orange-950` | `#431407` | Maximum-depth orange |

#### Ink — Structural neutrals

| Token | Hex | Use |
|-------|-----|-----|
| `ink-50` | `#F8FAFC` | Page background (light mode) |
| `ink-100` | `#F1F5F9` | Card backgrounds · ghost buttons |
| `ink-200` | `#E2E8F0` | Borders · dividers · input outlines |
| `ink-300` | `#CBD5E1` | Body text on dark backgrounds |
| `ink-400` | `#94A3B8` | Disabled text · placeholders |
| `ink-500` | `#64748B` | Muted text · captions · metadata |
| `ink-600` | `#475569` | Body text |
| `ink-700` | `#334155` | Subheadings · secondary headings |
| **`ink-800`** | **`#1E293B`** | **Admin chrome · premium dark surfaces** |
| `ink-900` | `#0F172A` | Primary text · headings · hero dark |
| `ink-950` | `#020617` | Deepest surfaces (discipline · footer) |

### 1.2 Semantic aliases

Use these in component code wherever possible. They abstract intent from specific stops, so a future palette migration only touches this layer.

| Alias | Maps to | Use |
|-------|---------|-----|
| `color-brand` | `teal-700` | Primary brand colour |
| `color-brand-hover` | `teal-600` | Primary hover state |
| `color-brand-active` | `teal-800` | Primary active/pressed state |
| `color-accent` | `orange-700` | Accent/warm colour |
| `color-accent-hover` | `orange-600` | Accent hover state |
| `color-accent-active` | `orange-800` | Accent active/pressed state |
| `color-surface` | `#FFFFFF` | Card/elevated surface |
| `color-surface-page` | `ink-50` | Page background |
| `color-surface-dark` | `ink-800` | Dark surfaces (admin chrome) |
| `color-surface-deepest` | `ink-950` | Deepest dark (hero, footer) |
| `color-text` | `ink-900` | Primary text |
| `color-text-body` | `ink-600` | Body text |
| `color-text-muted` | `ink-500` | Muted/secondary text |
| `color-text-disabled` | `ink-400` | Disabled text |
| `color-text-inverse` | `ink-50` | Text on dark surfaces |
| `color-border` | `ink-200` | Borders, dividers |
| `color-border-strong` | `ink-300` | Stronger borders |
| `color-focus-ring` | `teal-500` | Keyboard focus ring (40% alpha) |

### 1.3 Status tokens

For slot availability and booking states.

| Status | Background | Indicator | Text | Treatment |
|--------|-----------|-----------|------|-----------|
| **Available** | `teal-100` | `teal-700` | `teal-900` | Tinted |
| **Limited** | `orange-100` | `orange-700` | `orange-900` | Tinted |
| **Fully booked** | `ink-200` | `ink-600` | `ink-900` | Tinted |
| **Cancelled** | `ink-200` | `ink-500` | `ink-700` | Tinted, strikethrough |
| **Confirmed** ✓ | `orange-700` | `white` | `white` | **Filled** |

The confirmed pill is the only filled state — the booked-and-paid moment earns the visual weight.

### 1.4 Dark mode (future)

Out of scope for v1 but the palette supports it:

| Token | Light | Dark |
|-------|-------|------|
| Page background | `ink-50` | `ink-950` |
| Card surface | `#FFFFFF` | `ink-900` |
| Border | `ink-200` | `ink-700` |
| Primary text | `ink-900` | `ink-50` |
| Body text | `ink-600` | `ink-300` |
| Brand | `teal-700` | `teal-400` |
| Accent | `orange-700` | `orange-400` |

---

## 2. Typography

### 2.1 Font families

| Token | Family | Use | Source |
|-------|--------|-----|--------|
| `font-sans` | **Manrope** | Display, body, UI | Google Fonts |
| `font-mono` | **IBM Plex Mono** | Codes, tokens, technical labels, booking references | Google Fonts |

Manrope is a humanist geometric sans-serif with slightly open counters and warmer letterforms than Inter. IBM Plex Mono has subtle book-typography character — it reads more friendly than typical dev-tool monos.

Import via Google Fonts:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@200;300;400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### 2.2 Font weights

Manrope weights used (subset chosen from available 200–800):

| Token | Weight | Use |
|-------|--------|-----|
| `font-light` | 300 | Decorative separators only |
| `font-normal` | 400 | Body text default |
| `font-medium` | 500 | Slightly emphasised body |
| `font-semibold` | 600 | Subheadings, button labels, links |
| `font-bold` | 700 | Section titles, card titles |
| `font-extrabold` | 800 | Hero titles, brand-mark display |

IBM Plex Mono weights:

| Token | Weight | Use |
|-------|--------|-----|
| `font-mono-normal` | 400 | Body monospaced (booking refs) |
| `font-mono-medium` | 500 | Default for tokens, section labels |
| `font-mono-semibold` | 600 | Bold technical labels |

### 2.3 Font sizes

A modular scale built on a 16px base:

| Token | Size (rem / px) | Line height | Use |
|-------|-----------------|-------------|-----|
| `text-xs` | 0.6875rem / 11px | 1.5 | Eyebrow tags, very small labels |
| `text-sm` | 0.8125rem / 13px | 1.55 | Captions, table headers, mono labels |
| `text-base` | 0.9375rem / 15px | 1.65 | Body text default |
| `text-lg` | 1.0625rem / 17px | 1.65 | Lead paragraphs, important body |
| `text-xl` | 1.25rem / 20px | 1.4 | Card titles, dialog titles |
| `text-2xl` | 1.5rem / 24px | 1.25 | H3, family titles |
| `text-3xl` | 1.875rem / 30px | 1.2 | H2 in dense surfaces |
| `text-4xl` | 2.25rem / 36px | 1.1 | Section titles (small) |
| `text-5xl` | 3rem / 48px | 1.05 | Section titles (large) |
| `text-6xl` | 4rem / 64px | 1 | Hero titles (small) |
| `text-7xl` | 5rem / 80px | 0.98 | Hero titles (large) |

For responsive scaling, use clamp:

```css
.hero-title { font-size: clamp(3rem, 8vw, 7rem); }
.section-title { font-size: clamp(2.25rem, 5vw, 4.5rem); }
```

### 2.4 Letter spacing

Manrope reads best with a slight negative tracking on display sizes:

| Token | Value | Use |
|-------|-------|-----|
| `tracking-tightest` | -0.04em | Hero titles |
| `tracking-tighter` | -0.035em | Section titles |
| `tracking-tight` | -0.025em | Card titles, H1/H2 |
| `tracking-snug` | -0.015em | Subheadings |
| `tracking-normal` | 0 | Body text |
| `tracking-wide` | 0.08em | Mono uppercase labels |
| `tracking-wider` | 0.12em | Section number labels |
| `tracking-widest` | 0.18em | Eyebrow text |

### 2.5 Text styles (composite)

Pre-composed style combinations for common cases:

```css
/* Hero title */
.text-hero {
  font-family: var(--font-sans);
  font-weight: 800;
  font-size: clamp(3rem, 8vw, 7rem);
  line-height: 0.98;
  letter-spacing: -0.035em;
}

/* Section title */
.text-section-title {
  font-family: var(--font-sans);
  font-weight: 700;
  font-size: clamp(2.25rem, 5vw, 4.5rem);
  line-height: 1.05;
  letter-spacing: -0.03em;
}

/* Card title */
.text-card-title {
  font-family: var(--font-sans);
  font-weight: 700;
  font-size: 1.25rem;
  line-height: 1.2;
  letter-spacing: -0.02em;
}

/* Body */
.text-body {
  font-family: var(--font-sans);
  font-weight: 400;
  font-size: 0.9375rem;
  line-height: 1.65;
}

/* Section label (eyebrow) */
.text-eyebrow {
  font-family: var(--font-mono);
  font-weight: 500;
  font-size: 0.75rem;
  letter-spacing: 0.2em;
  text-transform: uppercase;
}

/* Mono code/token */
.text-mono {
  font-family: var(--font-mono);
  font-weight: 500;
  font-size: 0.8125rem;
}
```

---

## 3. Spacing

A 4px-based scale. Tailwind's default `spacing` scale is compatible — these are the tokens we actually use:

| Token | Value (rem / px) | Use |
|-------|------------------|-----|
| `space-0` | 0 | Reset |
| `space-1` | 0.25rem / 4px | Tightest gaps |
| `space-2` | 0.5rem / 8px | Icon-to-text spacing |
| `space-3` | 0.75rem / 12px | Compact gaps |
| `space-4` | 1rem / 16px | Default gap |
| `space-5` | 1.25rem / 20px | Inter-paragraph |
| `space-6` | 1.5rem / 24px | Card padding (compact) |
| `space-8` | 2rem / 32px | Card padding (default) |
| `space-10` | 2.5rem / 40px | Family panel padding |
| `space-12` | 3rem / 48px | Section internal spacing |
| `space-16` | 4rem / 64px | Container horizontal padding |
| `space-20` | 5rem / 80px | Section header gaps |
| `space-24` | 6rem / 96px | Discipline section padding |
| `space-28` | 7rem / 112px | Section vertical padding |
| `space-32` | 8rem / 128px | Hero padding |

---

## 4. Border radius

| Token | Value | Use |
|-------|-------|-----|
| `radius-none` | 0 | Hard edges |
| `radius-sm` | 4px | Inline code, small chips |
| `radius-md` | 6px | Form inputs, contrast samples |
| `radius-lg` | 8px | Buttons, tag pills, default cards |
| `radius-xl` | 12px | Showcase cards, modals |
| `radius-2xl` | 14px | Pairing canvases, prominent cards |
| `radius-full` | 9999px | Status badges, confirmation pill, dots |

---

## 5. Elevation (shadows)

A restrained shadow scale. Most surfaces use borders, not shadows.

| Token | Value | Use |
|-------|-------|-----|
| `shadow-none` | none | Default |
| `shadow-xs` | `0 1px 2px rgba(0,0,0,0.04)` | Subtle elevation on cards |
| `shadow-sm` | `0 1px 3px rgba(0,0,0,0.08)` | Default card elevation |
| `shadow-md` | `0 4px 12px rgba(0,0,0,0.08)` | Hover state for cards/buttons |
| `shadow-lg` | `0 10px 24px rgba(0,0,0,0.12)` | Dropdowns, popovers |
| `shadow-xl` | `0 20px 40px rgba(0,0,0,0.15)` | Modals |
| `shadow-focus-brand` | `0 0 0 3px rgba(15,118,110,0.25)` | Keyboard focus on teal elements |
| `shadow-focus-accent` | `0 0 0 3px rgba(194,65,12,0.25)` | Keyboard focus on orange elements |

Brand-coloured shadows for button hover states:

| Token | Value | Use |
|-------|-------|-----|
| `shadow-brand-hover` | `0 4px 12px rgba(15,118,110,0.25)` | Teal CTA hover lift |
| `shadow-accent-hover` | `0 4px 12px rgba(194,65,12,0.25)` | Orange CTA hover lift |

---

## 6. Motion

| Token | Duration | Easing | Use |
|-------|----------|--------|-----|
| `motion-fast` | 100ms | ease-out | Micro-interactions (button press) |
| `motion-base` | 150ms | ease-out | Hover transitions, default |
| `motion-slow` | 250ms | cubic-bezier(0.4, 0, 0.2, 1) | Modal/drawer enter |
| `motion-slower` | 400ms | cubic-bezier(0.4, 0, 0.2, 1) | Page transitions |

Custom easings:

| Token | Value | Use |
|-------|-------|-----|
| `ease-out-soft` | `cubic-bezier(0.4, 0, 0.2, 1)` | Default for most motion |
| `ease-out-back` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Confirmation moments (subtle overshoot) |
| `ease-in-out-soft` | `cubic-bezier(0.45, 0, 0.55, 1)` | Looping/return animations |

**Reduced motion**: respect `prefers-reduced-motion: reduce` and disable non-essential transitions.

---

## 7. Z-index

A discrete scale to prevent z-index wars:

| Token | Value | Use |
|-------|-------|-----|
| `z-base` | 0 | Default page content |
| `z-raised` | 1 | Cards on hover |
| `z-dropdown` | 10 | Dropdowns, popovers |
| `z-sticky` | 20 | Sticky headers |
| `z-fixed` | 30 | Fixed navigation |
| `z-modal-backdrop` | 90 | Modal overlay |
| `z-modal` | 100 | Modal content |
| `z-toast` | 1000 | Toasts/notifications |
| `z-tooltip` | 9000 | Tooltips (always top) |

---

## 8. Breakpoints

Mobile-first. Min-width values used as media query thresholds:

| Token | Min-width | Tailwind | Use |
|-------|-----------|----------|-----|
| `screen-sm` | 640px | `sm:` | Small tablet, large phone landscape |
| `screen-md` | 768px | `md:` | Tablet |
| `screen-lg` | 1024px | `lg:` | Small desktop, large tablet |
| `screen-xl` | 1280px | `xl:` | Standard desktop |
| `screen-2xl` | 1600px | `2xl:` | Large desktop (max content width) |

The maximum content container width is **1600px**. Beyond that, content centres with growing margins.

---

## 9. Iconography

- **Icon library**: Heroicons (built into Phoenix's default stack)
- **Default size**: 20px (1.25rem)
- **Sizes**: 16px (sm), 20px (default), 24px (md), 32px (lg)
- **Stroke width**: 1.5px for outlined icons, solid for emphasis
- **Colour**: inherits from text colour by default; never colour an icon a different hue from its label without strong reason

---

## 10. Five rules nobody breaks

The discipline of the system. Non-negotiable.

1. **Teal anchors the page.** Every screen has at least one `teal-700` element. Orange is the partner, not the lead.
2. **Orange does real work, but never alone.** Orange can drive section labels, callouts, ribbons, and the confirmed-booking pill — but every surface needs a teal element to anchor it.
3. **Ink is for the considered moments.** Admin chrome, audit logs, the supervision-tree health view. Ink signals "considered, sophisticated, distinctly not marketing-emphasis."
4. **The CONFIRMED badge is filled, not tinted.** Status badges are tinted (light bg + dark text). The confirmed-booking pill is filled (`orange-700` bg, white text). The booked-and-paid moment earns its visual weight.
5. **The tokens file is the source of truth.** No ad-hoc hex values in components. Reach for `bg-orange-700`, never `bg-[#C2410C]`. CI hooks catch the latter.

---

## 11. Implementation

Two implementation files are provided alongside this spec:

- **`tailwind.config.js`** — drop-in Tailwind extension exposing every token as a utility class
- **`tokens.css`** — CSS custom properties for projects not using Tailwind, or for runtime token access

Both derive their values directly from this document. If a value changes here, update both implementations.

### Usage in Phoenix LiveView components

```heex
<button class="bg-teal-700 hover:bg-teal-600 text-white font-semibold
               px-6 py-3 rounded-lg transition-colors duration-150
               focus:outline-none focus:ring-2 focus:ring-teal-500/30">
  Book this slot
</button>
```

### Usage with CSS custom properties

```css
.book-button {
  background: var(--color-brand);
  color: var(--color-text-inverse);
  font-family: var(--font-sans);
  font-weight: 600;
  padding: var(--space-3) var(--space-6);
  border-radius: var(--radius-lg);
  transition: background var(--motion-base) var(--ease-out-soft);
}
.book-button:hover { background: var(--color-brand-hover); }
```

---

## 12. Versioning & change control

This is **v1.0**. Subsequent versions bump as follows:

- **Patch (1.0.x)** — tweaks to non-brand stops, semantic alias adjustments, documentation edits
- **Minor (1.x.0)** — new tokens added (e.g. additional spacing values, new shadow variants)
- **Major (x.0.0)** — brand colours or typeface changes; requires full design review

Changes must be reflected in this document, `tailwind.config.js`, and `tokens.css` in a single commit. CI checks for drift between the three files.

---

*End of specification.*
