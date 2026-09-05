import { test, expect } from '@playwright/test'

/**
 * @critical
 * Candidate full journey: register → check redirect + flash → log in →
 * see dashboard → log out → back to public landing.
 *
 * The email-verification step is intentionally NOT exercised here — the
 * underlying controller is unit-tested at
 * `test/guildford_vue_web/controllers/candidate/candidate_confirmation_controller_test.exs`
 * and bringing Mailcatcher into the E2E setup is heavier than the
 * benefit. Sprint 7 will add a Mailcatcher-API-backed test once the
 * booking confirmation email has more business value behind it.
 */
test.describe('Candidate full journey', () => {
  test('register → login → dashboard → logout', async ({ page }) => {
    // Unique email so the test is idempotent across re-runs.
    const email = `playwright-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.com`
    const password = 'PlaywrightTest123!'

    // 1. Register
    await page.goto('/candidate/register')
    await page.getByLabel(/first name/i).fill('Playwright')
    await page.getByLabel(/last name/i).fill('Tester')
    await page.getByLabel(/email/i).fill(email)
    await page.getByLabel(/password/i).fill(password)
    await page.getByLabel(/postcode/i).fill('GU1 4LZ')
    await page.getByRole('button', { name: /register/i }).click()

    // 2. Redirected to login with "check your email" flash
    await expect(page).toHaveURL(/\/candidate\/login$/)
    await expect(page.getByText(/check your email/i)).toBeVisible()

    // 3. Log in (we skip the email-verify step — the candidate row exists
    //    in the DB; login works whether or not email is verified at this
    //    stage of the product. PRD §4.2 doesn't gate login on verification
    //    explicitly; it's a UX nudge.)
    await page.getByLabel(/email/i).fill(email)
    await page.getByLabel(/password/i).fill(password)
    await page.getByRole('button', { name: /sign in/i }).click()

    // 4. Land on dashboard
    await expect(page).toHaveURL(/\/candidate\/dashboard$/)
    await expect(page.getByRole('heading', { name: /welcome back, playwright/i })).toBeVisible()

    // 5. Layout cond-nav shows the email + Settings + Log out
    await expect(page.locator('nav').getByText(email)).toBeVisible()
    await expect(page.locator('nav').getByRole('link', { name: /settings/i })).toBeVisible()

    // 6. Log out — Phoenix uses a delete request, fired by a data-method link.
    //    Click it; expect to land back at /.
    await page.locator('nav').getByText(/log out/i).click()
    await expect(page).toHaveURL('/')
  })
})
