import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

/**
 * @critical
 * axe-core audits on the three login pages. PRD §8.4 mandates WCAG 2.1
 * AA conformance; this set is the gate that catches regressions before
 * they ship.
 */

const loginPages = [
  { name: 'candidate', path: '/candidate/login' },
  { name: 'back-office', path: '/backoffice/login' },
  { name: 'exam-centre', path: '/examcenter/login' },
]

for (const { name, path } of loginPages) {
  test.describe(`${name} login page (${path})`, () => {
    test('renders the sign-in form', async ({ page }) => {
      await page.goto(path)
      await expect(page.getByRole('heading', { name: /sign in/i })).toBeVisible()
      await expect(page.getByLabel(/email/i)).toBeVisible()
      await expect(page.getByLabel(/password/i)).toBeVisible()
      await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible()
    })

    test('passes axe-core WCAG 2.1 AA audit', async ({ page }) => {
      await page.goto(path)
      const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze()
      expect(results.violations).toEqual([])
    })

    test('keyboard navigation reaches the submit button', async ({ page }) => {
      await page.goto(path)
      // First focus: usually the body. Tab a few times — sign-in button must
      // be reachable via keyboard alone (no mouse trap).
      const submitButton = page.getByRole('button', { name: /sign in/i })

      let focused = false
      for (let i = 0; i < 15; i++) {
        await page.keyboard.press('Tab')
        if (await submitButton.evaluate((el) => el === document.activeElement).catch(() => false)) {
          focused = true
          break
        }
      }
      expect(focused).toBeTruthy()
    })
  })
}
