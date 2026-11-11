import fs from "node:fs";

let auth = fs.readFileSync("lib/auth.ts", "utf8");
const profileLine = "        const profile = await profileResponse.json();";
if (!auth.includes(profileLine)) throw new Error("Unexpected GitHub profile handler");
auth = auth.replace(profileLine, `${profileLine}
        if (String(profile.id) !== process.env.ALLOWED_GITHUB_USER_ID) return null;`);
for (const line of [
  'import { emailOTP } from "better-auth/plugins";\n',
  'import { sendEmail } from "@/lib/mailer";\n',
  'import { LoginEmailTemplate } from "@/components/email/login";\n',
  'import { render } from "@react-email/render";\n',
]) {
  if (!auth.includes(line)) throw new Error("Unexpected email authentication imports");
  auth = auth.replace(line, "");
}
const pluginStart = auth.indexOf("  plugins: [\n");
if (pluginStart < 0 || !auth.slice(pluginStart).includes("emailOTP({")) {
  throw new Error("Unexpected authentication plugins");
}
auth = auth.slice(0, pluginStart) + "  plugins: [nextCookies()],\n});\n";
fs.writeFileSync("lib/auth.ts", auth);
fs.copyFileSync(new URL("./sign-in.tsx", import.meta.url), "components/sign-in.tsx");
fs.copyFileSync(new URL("./owner-access.test.ts", import.meta.url), "scripts/owner-access.test.ts");
fs.writeFileSync("app/(auth)/sign-in/collaborator/page.tsx", `import { redirect } from "next/navigation";

export default function Page() {
  redirect("/sign-in");
}
`);

let githubAccount = fs.readFileSync("lib/github-account.ts", "utf8");
const accountReader = `const getGithubAccount = cache(async (userId: string) => {
  return db.query.accountTable.findFirst({
    where: and(
      eq(accountTable.userId, userId),
      eq(accountTable.providerId, "github")
    )
  });
});`;
if (!githubAccount.includes(accountReader)) throw new Error("Unexpected GitHub account reader");
githubAccount = githubAccount.replace(accountReader, `const getGithubAccount = cache(async (userId: string) => {
  const account = await db.query.accountTable.findFirst({
    where: and(
      eq(accountTable.userId, userId),
      eq(accountTable.providerId, "github")
    )
  });
  if (!account) return undefined;

  const tokens = await auth.api.getAccessToken({
    body: { accountId: account.id, userId },
  });
  return {
    ...account,
    accessToken: tokens.accessToken,
    accessTokenExpiresAt: tokens.accessTokenExpiresAt ?? account.accessTokenExpiresAt,
  };
});`);
githubAccount = 'import { auth } from "@/lib/auth";\n' + githubAccount;
fs.writeFileSync("lib/github-account.ts", githubAccount);
fs.copyFileSync(new URL("./token-refresh.test.mjs", import.meta.url), "scripts/token-refresh.test.mjs");
