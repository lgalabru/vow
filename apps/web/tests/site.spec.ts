import { expect, test } from '@playwright/test';

test('landing page presents the product without signing anything', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('3-FactorAuthentication.');
  // The illustrations are pictures of the apps, not control surfaces.
  await expect(page.getByRole('button')).toHaveCount(0);
  await page.locator('#ipad').scrollIntoViewIfNeeded();
  await expect(page.getByRole('heading', { name: 'Sign it yourself.' })).toBeVisible();
  await page.locator('#features').scrollIntoViewIfNeeded();
  await expect(page.getByText('Offline means offline.')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Squads' })).toBeVisible();
  await page.locator('#mac').scrollIntoViewIfNeeded();
  await expect(
    page.getByRole('heading', { name: 'The ceremony happens on the Mac.' }),
  ).toBeVisible();
  await expect(
    page.getByText('Illustration with sample data. No signing keys are used.'),
  ).toBeAttached();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
});

test('the story follows the scroll through all three factors', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    const story = document.querySelector<HTMLElement>('#ipad')!;
    const top = story.getBoundingClientRect().top + window.scrollY;
    window.scrollTo({ top: top + (story.offsetHeight - window.innerHeight) * 0.95 });
  });
  await expect(page.getByRole('heading', { name: 'Three factors. One approval.' })).toBeVisible();
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

test('nothing widens the page on the way down', async ({ page }) => {
  await page.goto('/');
  const height = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y <= height; y += 400) {
    await page.evaluate((top) => window.scrollTo({ top, behavior: 'instant' }), y);
    // The page clips sideways overflow on the body. Lift that, and the layout
    // must still be no wider than the screen: nothing may rely on the clip.
    const extra = await page.evaluate(() => {
      const { body, documentElement: root } = document;
      body.style.overflowX = 'visible';
      const width = root.scrollWidth - root.clientWidth;
      body.style.overflowX = '';
      return width;
    });
    expect(extra, `sideways overflow at scroll ${y}`).toBeLessThanOrEqual(0);
  }
});
