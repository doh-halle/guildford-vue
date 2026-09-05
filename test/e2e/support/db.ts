/**
 * Database reset helpers for Playwright E2E tests.
 *
 * The Phoenix server in `MIX_ENV=test` shares the test DB. Between scenarios
 * we call `resetDatabase()` to truncate volatile tables. The helper uses a
 * Phoenix-exposed `POST /test/support/reset-db` endpoint that's mounted only
 * when `MIX_ENV=test`. (Endpoint to be added in Sprint 1 alongside the auth
 * factories.)
 */
export async function resetDatabase(request: any): Promise<void> {
  if (process.env.PLAYWRIGHT_SKIP_DB_RESET) return
  // Endpoint mounted by Sprint 1; safe no-op in Sprint 0 because the landing
  // page reads no DB state.
  const res = await request.post('/test/support/reset-db').catch(() => null)
  if (res && res.status() >= 500) {
    throw new Error(`resetDatabase failed: HTTP ${res.status()}`)
  }
}
