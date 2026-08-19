import { expect, test } from "@playwright/test";

test("starts a real browser context", async ({ page }) => {
  await page.setContent("<main>Gainer browser tests are ready.</main>");

  await expect(page.getByRole("main")).toHaveText(
    "Gainer browser tests are ready.",
  );
});
