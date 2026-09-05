import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright configuration for Guildford Vue end-to-end tests.
 *
 * In CI we spawn a fresh `mix phx.server` on port 4002 (matches config/test.exs
 * test endpoint port). Locally we let it reuse if you already have one running.
 *
 * Projects cover the responsive matrix: desktop Chrome / Firefox / Safari plus
 * mobile iPhone and Pixel — PRD §8.3 mandates mobile-first.
 */
export default defineConfig({
  testDir: './test/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: [['html', { outputFolder: 'test/e2e/playwright-report', open: 'never' }]],

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:4002',
    trace: 'on-first-retry',
    video: 'retain-on-failure',
  },

  webServer: {
    command: 'MIX_ENV=test mix phx.server',
    url: 'http://localhost:4002',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },

  projects: [
    { name: 'desktop-chrome',   use: { ...devices['Desktop Chrome'] } },
    { name: 'desktop-firefox',  use: { ...devices['Desktop Firefox'] } },
    { name: 'desktop-safari',   use: { ...devices['Desktop Safari'] } },
    { name: 'mobile-iphone',    use: { ...devices['iPhone 14'] } },
    { name: 'mobile-android',   use: { ...devices['Pixel 7'] } },
  ],
})
