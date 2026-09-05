import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

/**
 * Sprint 11 Slice 4 — axe-core sweep across every public + auth
 * landing page that does NOT require an authenticated session.
 * Pages behind candidate / admin auth are covered by their own
 * spec files (auth_logins.spec.ts already audits the three login
 * pages).
 *
 * Tags: `wcag2a` + `wcag2aa`. Zero violations is the PRD §8.4
 * acceptance criterion.
 */

const publicPages: Array<{ path: string; name: string }> = [
  { path: '/', name: 'Landing page' },
  { path: '/search', name: 'Public centre search' },
  { path: '/candidate/login', name: 'Candidate login' },
  { path: '/candidate/register', name: 'Candidate registration' },
  { path: '/candidate/forgot-password', name: 'Candidate forgot password' },
  { path: '/backoffice/login', name: 'Back-office login' },
  { path: '/backoffice/forgot-password', name: 'Back-office forgot password' },
  { path: '/examcenter/login', name: 'Exam-centre login' },
  { path: '/examcenter/forgot-password', name: 'Exam-centre forgot password' },
]

test.describe('Public pages — axe-core sweep', () => {
  for (const { path, name } of publicPages) {
    test(`${name} (${path}) — zero WCAG 2.1 AA violations`, async ({ page }) => {
      await page.goto(path)
      const results = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa'])
        .analyze()

      // When violations exist, dump them so CI logs are actionable.
      if (results.violations.length > 0) {
        console.log(`axe-core violations on ${path}:`)
        for (const v of results.violations) {
          console.log(`- [${v.impact}] ${v.id}: ${v.description}`)
          console.log(`  help: ${v.helpUrl}`)
        }
      }

      expect(results.violations).toEqual([])
    })
  }
})

test.describe('Mobile viewport — axe-core', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('Landing page (mobile) — zero violations', async ({ page }) => {
    await page.goto('/')
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze()
    expect(results.violations).toEqual([])
  })

  test('Search page (mobile) — zero violations', async ({ page }) => {
    await page.goto('/search')
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze()
    expect(results.violations).toEqual([])
  })
})
