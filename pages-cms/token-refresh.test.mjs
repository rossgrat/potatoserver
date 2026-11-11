import assert from "node:assert/strict";
import { test } from "node:test";

process.env.BASE_URL = "https://cms.example.test";
process.env.DATABASE_URL = "postgresql://test:test@127.0.0.1:5432/test";
process.env.BETTER_AUTH_SECRET = "test-only-secret-with-at-least-32-characters";

const { auth } = await import("../lib/auth.ts");
const { db } = await import("../db/index.ts");
const { getGithubAccount } = await import("../lib/github-account.ts");

test("expired GitHub token is renewed before repository access", async (t) => {
  const expiresAt = new Date(Date.now() + 3600000);
  t.mock.method(db.query.accountTable, "findFirst", async () => ({
    id: "account-1", userId: "owner-1", accountId: "69823943", providerId: "github",
    accessToken: "expired-token", accessTokenExpiresAt: new Date(0),
  }));
  const refresh = t.mock.method(auth.api, "getAccessToken", async () => ({
    accessToken: "renewed-token", accessTokenExpiresAt: expiresAt,
  }));
  const account = await getGithubAccount("owner-1");
  assert.equal(account.accessToken, "renewed-token");
  assert.equal(account.accessTokenExpiresAt, expiresAt);
  assert.deepEqual(refresh.mock.calls[0].arguments[0], {
    body: { accountId: "account-1", userId: "owner-1" },
  });
});

test("an absent GitHub account does not request a token", async (t) => {
  t.mock.method(db.query.accountTable, "findFirst", async () => undefined);
  const refresh = t.mock.method(auth.api, "getAccessToken", async () => {
    throw new Error("Unexpected token request");
  });
  assert.equal(await getGithubAccount("missing-owner"), undefined);
  assert.equal(refresh.mock.callCount(), 0);
});
