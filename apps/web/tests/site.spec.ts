import { expect, test } from '@playwright/test';

test('approval preview supports keyboard navigation without signing', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Shared control.Personal approval.',
  );
  const authorize = page.getByRole('tab', { name: '2 Authorize' });
  await expect(authorize).toHaveAttribute('aria-selected', 'true');
  await authorize.focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('tab', { name: '3 Export' })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.getByText('Bring your approval back to the team.')).toBeVisible();
  await page.getByRole('tab', { name: '1 Review' }).click();
  await expect(page.getByText('Understand the request.')).toBeVisible();
  await expect(
    page.getByText('Interactive preview with sample data. No signing keys are used.'),
  ).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
});

test('availability and limitations are discoverable', async ({ page }) => {
  await page.goto('/');
  await page.getByText('Can I use Vow with a live treasury?', { exact: true }).click();
  await expect(page.getByText(/There is no public App Store or TestFlight release/)).toBeVisible();
  await page.getByRole('link', { name: /In development/ }).click();
  await expect(
    page.getByRole('heading', { name: 'Taking the time to get it right.' }),
  ).toBeInViewport();
});

test('Apple association is direct JSON for the signing app', async ({ request }) => {
  const response = await request.get('/.well-known/apple-app-site-association', {
    maxRedirects: 0,
  });
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toContain('application/json');
  expect(await response.json()).toEqual({
    webcredentials: { apps: ['4HY7TSGF6M.org.vow.prototype'] },
  });
});
