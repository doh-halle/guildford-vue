import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

/**
 * @critical
 * Landing page. Verifies the three auth entry points and a clean axe-core
 * WCAG 2.1 AA audit (PRD §8.4).
 */
test.describe('Landing page', () => {
  test('renders headline and three auth entry points', async ({ page }) => {
    await page.goto('/')

    await expect(page.getByRole('heading', { name: /book your uk examination slot/i })).toBeVisible()
    await expect(page.getByRole('link', { name: /candidate sign in/i })).toBeVisible()
    await expect(page.getByRole('link', { name: /exam centre sign in/i })).toBeVisible()
    await expect(page.getByRole('link', { name: /back office/i })).toBeVisible()
  })

  test('passes axe-core WCAG 2.1 AA audit', async ({ page }) => {
    await page.goto('/')
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze()
    expect(results.violations).toEqual([])
  })

  test('health endpoint returns ok', async ({ request }) => {
    const res = await request.get('/health')
    expect(res.status()).toBe(200)
    expect(await res.json()).toEqual({ status: 'ok', app: 'guildford_vue' })
  })
})
