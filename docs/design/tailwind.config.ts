/**
 * Guildford Vue — Tailwind CSS configuration
 *
 * Generated from design_tokens.md v1.0
 * Drop into project root. Do not modify token values directly here —
 * update design_tokens.md first, then sync this file to match.
 */

import type { Config } from 'tailwindcss'
import defaultTheme from 'tailwindcss/defaultTheme'

const config: Config = {
  content: [
    './lib/**/*.{ex,heex}',
    './assets/js/**/*.js',
    './assets/css/**/*.css',
  ],

  theme: {
    extend: {
      // ============================================
      // COLOUR
      // ============================================
      colors: {
        // Teal — Primary brand
        teal: {
          50:  '#F0FDFA',
          100: '#CCFBF1',
          200: '#99F6E4',
          300: '#5EEAD4',
          400: '#2DD4BF',
          500: '#14B8A6',
          600: '#0D9488',
          700: '#0F766E', // brand
          800: '#115E59',
          900: '#134E4A',
          950: '#042F2E',
        },
        // Orange — Accent & confirmation
        orange: {
          50:  '#FFF7ED',
          100: '#FFEDD5',
          200: '#FED7AA',
          300: '#FDBA74',
          400: '#FB923C',
          500: '#F97316',
          600: '#EA580C',
          700: '#C2410C', // brand accent
          800: '#9A3412',
          900: '#7C2D12',
          950: '#431407',
        },
        // Ink — Structural neutrals
        ink: {
          50:  '#F8FAFC',
          100: '#F1F5F9',
          200: '#E2E8F0',
          300: '#CBD5E1',
          400: '#94A3B8',
          500: '#64748B',
          600: '#475569',
          700: '#334155',
          800: '#1E293B', // brand dark
          900: '#0F172A',
          950: '#020617',
        },
        // Semantic aliases
        brand: {
          DEFAULT: '#0F766E',  // teal-700
          hover:   '#0D9488',  // teal-600
          active:  '#115E59',  // teal-800
        },
        accent: {
          DEFAULT: '#C2410C',  // orange-700
          hover:   '#EA580C',  // orange-600
          active:  '#9A3412',  // orange-800
        },
      },

      // ============================================
      // TYPOGRAPHY
      // ============================================
      fontFamily: {
        sans: ['Manrope', ...defaultTheme.fontFamily.sans],
        mono: ['IBM Plex Mono', ...defaultTheme.fontFamily.mono],
      },

      fontSize: {
        'xs':   ['0.6875rem', { lineHeight: '1.5' }],     // 11px — eyebrow tags
        'sm':   ['0.8125rem', { lineHeight: '1.55' }],    // 13px — captions, mono labels
        'base': ['0.9375rem', { lineHeight: '1.65' }],    // 15px — body default
        'lg':   ['1.0625rem', { lineHeight: '1.65' }],    // 17px — lead body
        'xl':   ['1.25rem',   { lineHeight: '1.4' }],     // 20px — card titles
        '2xl':  ['1.5rem',    { lineHeight: '1.25' }],    // 24px — H3
        '3xl':  ['1.875rem',  { lineHeight: '1.2' }],     // 30px — H2 dense
        '4xl':  ['2.25rem',   { lineHeight: '1.1' }],     // 36px — section titles small
        '5xl':  ['3rem',      { lineHeight: '1.05' }],    // 48px — section titles large
        '6xl':  ['4rem',      { lineHeight: '1' }],       // 64px — hero small
        '7xl':  ['5rem',      { lineHeight: '0.98' }],    // 80px — hero large
      },

      fontWeight: {
        light:      '300',
        normal:     '400',
        medium:     '500',
        semibold:   '600',
        bold:       '700',
        extrabold:  '800',
      },

      letterSpacing: {
        tightest: '-0.04em',
        tighter:  '-0.035em',
        tight:    '-0.025em',
        snug:     '-0.015em',
        normal:   '0',
        wide:     '0.08em',
        wider:    '0.12em',
        widest:   '0.18em',
      },

      // ============================================
      // BORDER RADIUS
      // ============================================
      borderRadius: {
        'none':  '0',
        'sm':    '4px',
        'md':    '6px',
        'lg':    '8px',
        'xl':    '12px',
        '2xl':   '14px',
        'full':  '9999px',
      },

      // ============================================
      // ELEVATION (BOX SHADOWS)
      // ============================================
      boxShadow: {
        'none':           'none',
        'xs':             '0 1px 2px rgba(0,0,0,0.04)',
        'sm':             '0 1px 3px rgba(0,0,0,0.08)',
        'md':             '0 4px 12px rgba(0,0,0,0.08)',
        'lg':             '0 10px 24px rgba(0,0,0,0.12)',
        'xl':             '0 20px 40px rgba(0,0,0,0.15)',
        'focus-brand':    '0 0 0 3px rgba(15,118,110,0.25)',
        'focus-accent':   '0 0 0 3px rgba(194,65,12,0.25)',
        'brand-hover':    '0 4px 12px rgba(15,118,110,0.25)',
        'accent-hover':   '0 4px 12px rgba(194,65,12,0.25)',
      },

      // ============================================
      // MOTION
      // ============================================
      transitionDuration: {
        'fast':   '100ms',
        'base':   '150ms',
        'slow':   '250ms',
        'slower': '400ms',
      },

      transitionTimingFunction: {
        'out-soft':     'cubic-bezier(0.4, 0, 0.2, 1)',
        'out-back':     'cubic-bezier(0.34, 1.56, 0.64, 1)',
        'in-out-soft':  'cubic-bezier(0.45, 0, 0.55, 1)',
      },

      // ============================================
      // Z-INDEX
      // ============================================
      zIndex: {
        'base':           '0',
        'raised':         '1',
        'dropdown':       '10',
        'sticky':         '20',
        'fixed':          '30',
        'modal-backdrop': '90',
        'modal':          '100',
        'toast':          '1000',
        'tooltip':        '9000',
      },

      // ============================================
      // BREAKPOINTS (mobile-first)
      // Tailwind's defaults are kept; 2xl is widened to match content max-width.
      // ============================================
      screens: {
        'sm':  '640px',
        'md':  '768px',
        'lg':  '1024px',
        'xl':  '1280px',
        '2xl': '1600px',
      },

      // ============================================
      // MAX WIDTHS
      // ============================================
      maxWidth: {
        'container': '1600px',  // Main app container
        'prose':     '38rem',    // Body text column
      },
    },
  },

  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),

    // Custom plugin: status badge variants
    function({ addComponents }) {
      addComponents({
        '.status-badge': {
          display: 'inline-flex',
          alignItems: 'center',
          gap: '0.5rem',
          padding: '0.4rem 0.9rem',
          borderRadius: '9999px',
          fontFamily: 'Manrope, sans-serif',
          fontSize: '0.8125rem',
          fontWeight: '600',
        },
        '.status-badge--available': {
          backgroundColor: '#CCFBF1',
          color: '#134E4A',
        },
        '.status-badge--limited': {
          backgroundColor: '#FFEDD5',
          color: '#7C2D12',
        },
        '.status-badge--fully-booked': {
          backgroundColor: '#E2E8F0',
          color: '#0F172A',
        },
        '.confirmed-pill': {
          display: 'inline-flex',
          alignItems: 'center',
          gap: '0.5rem',
          padding: '0.45rem 0.95rem',
          borderRadius: '9999px',
          backgroundColor: '#C2410C',
          color: '#FFFFFF',
          fontFamily: 'Manrope, sans-serif',
          fontSize: '0.8125rem',
          fontWeight: '600',
        },
      })
    },
  ],
}

export default config
