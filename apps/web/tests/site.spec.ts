import { expect, test } from '@playwright/test';

test('landing page presents the product without signing anything', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Shared control.Personal approval.',
  );
  await expect(
    page.getByText('Illustration with sample data. No signing keys are used.'),
  ).toBeVisible();
  // The illustration is a picture of the app, not a control surface.
  await expect(page.getByRole('button')).toHaveCount(0);
  await page
    .getByRole('heading', { name: 'Built for one decision at a time.' })
    .scrollIntoViewIfNeeded();
  await expect(page.getByText('Offline means offline.')).toBeVisible();
  await expect(page.getByText('Approvals collected')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
});

test('availability and limitations are discoverable', async ({ page }) => {
  await page.goto('/');
  await page.getByText('Can I use Vow with a live treasury?', { exact: true }).click();
  await expect(page.getByText(/There is no public App Store or TestFlight release/)).toBeVisible();
  await expect(page.getByRole('link', { name: /In development/ })).toHaveAttribute(
    'href',
    'https://github.com/lgalabru/vow',
  );
  await page.locator('#availability').scrollIntoViewIfNeeded();
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
