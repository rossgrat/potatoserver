import assert from "node:assert/strict";
import { test } from "node:test";

process.env.BASE_URL = "https://cms.example.test";
process.env.DATABASE_URL = "postgresql://test:test@127.0.0.1:5432/test";
process.env.BETTER_AUTH_SECRET = "test-only-secret-with-at-least-32-characters";

test("CMS owner access", async (t) => {
  const { auth } = await import("../lib/auth");
  const getUserInfo = auth.options.socialProviders.github.getUserInfo;
  const originalFetch = globalThis.fetch;
  let profileId = 69823943;
  let login = "rossgrat";
  const requests: string[] = [];
  globalThis.fetch = async (input) => {
    const url = String(input);
    requests.push(url);
    if (url === "https://api.github.com/user") {
      return Response.json({ id: profileId, login, email: "owner@example.test" });
    }
    if (url === "https://api.github.com/user/emails") {
      return Response.json([{ email: "owner@example.test", primary: true, verified: true }]);
    }
    throw new Error(`Unexpected request: ${url}`);
  };
  try {
    process.env.ALLOWED_GITHUB_USER_ID = "69823943";
    await t.test("allows the verified owner ID after a username change", async () => {
      login = "renamed-owner";
      const result = await getUserInfo({ accessToken: "test-token" });
      assert.equal(result?.user?.id, 69823943);
    });
    await t.test("rejects another ID even when its name and email match", async () => {
      profileId = 42;
      login = "rossgrat";
      requests.length = 0;
      assert.equal(await getUserInfo({ accessToken: "test-token" }), null);
      assert.deepEqual(requests, ["https://api.github.com/user"]);
    });
    await t.test("denies access when the owner configuration is missing", async () => {
      delete process.env.ALLOWED_GITHUB_USER_ID;
      profileId = 69823943;
      assert.equal(await getUserInfo({ accessToken: "test-token" }), null);
    });
    await t.test("disables email authentication", () => {
      const pluginIds: string[] = auth.options.plugins.map((plugin) => plugin.id);
      assert.equal(pluginIds.includes("email-otp"), false);
    });
  } finally {
    globalThis.fetch = originalFetch;
    delete process.env.ALLOWED_GITHUB_USER_ID;
  }
});
