# Pages CMS

Pages CMS edits the blog repository at `https://cms.grattafiori.dev`.
Cloudflare Tunnel forwards this hostname to Caddy at `127.0.0.1:80` on potatoserver.
Caddy forwards CMS requests to `pages-cms.pages-cms.svc.cluster.local:3000`.
Only the GitHub account `rossgrat` can sign in to this CMS.
The authentication callback accepts only GitHub user ID `69823943`, as set by `ALLOWED_GITHUB_USER_ID`.
A missing owner ID denies sign-in. Email sign-in is disabled.
GitHub repository permissions still control edits.
The GitHub App is installed only on `rossgrat/rossgrat.github.io`.

The application and PostgreSQL run in the K3s namespace `pages-cms`.
PostgreSQL stores login sessions, credentials, and cached repository data.
GitHub retains the authoritative posts and images.
The database does not publish a host port.

The image pins Pages CMS 2.1.8, Node 24.22.2, and their source or image digests.
PostgreSQL uses version 18.6 with a pinned digest.
The checked-in lockfile pins patched dependencies, including Next.js 16.4.6, Better Auth 1.7.20, and Tiptap 3.33.1.
The build uses Docker Buildx 0.38.2 and retains an npm download cache.
The `r4` image adds Zod 4.6.7, Nodemailer 10.5.0, and compatible form validation.
The deployment retains the stylesheet from [shadcn 3.8.5](https://github.com/shadcn-ui/ui/tree/shadcn%403.8.5) in `pages-cms/vendor/`.
It omits the component generator and its Zod 3 dependency.
Every image build tests that other GitHub identities are rejected and email authentication is disabled.
Repository requests use [Better Auth token renewal](https://better-auth.com/docs/concepts/oauth#get-access-token) when the GitHub access token expires.
The build also tests this renewal path, post forms, configuration errors, and both dependency security regressions.
The original Docker bootstrap ran database migrations in a separate container.
Review schema changes before updating the K3s application image.

## Security boundary

The CMS is public over HTTPS through Cloudflare Tunnel.
It does not require Tailscale or a separate Cloudflare Access login.
The owner restriction runs in the application after GitHub identifies the account.

Session cookies use Secure, HttpOnly, and SameSite=Lax.
These attributes restrict cookie transport, script access, and cross-site use.
The app rejects cross-site authentication requests and invalid webhook signatures.
The application runs as the non-root Node user.
The network policy allows Caddy to reach the application port.

A stolen GitHub account or CMS session can let an attacker act as you.
A compromised server or application can also expose the credentials stored there.
Protect your GitHub account with a [passkey or two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa/about-two-factor-authentication).
The owner restriction does not guarantee that the application has no vulnerabilities.

The GitHub App has access only to the blog repository.
It grants write access to Contents and Actions, plus read access to checks, statuses, and metadata.
Administration permission is disabled in both the app registration and installation.
The setup helper also removes that permission from new registrations.
Creating repositories from CMS templates is outside this deployment.
GitHub documents [how to change app permissions](https://docs.github.com/en/apps/maintaining-github-apps/modifying-a-github-app-registration#changing-the-permissions-of-a-github-app).

The November 11, 2026 review found one owner account, one active owner session, and no collaborators or invitations.
All thirteen authentication, token, validation, and dependency security tests passed.
All eight existing posts passed form validation, including both drafts. All eighteen images remained accessible.
The owner token read the repository but received 403 from the repository administration endpoint.
Unauthenticated content requests returned 401, and email-code login endpoints returned 404.
Password login was disabled in the deployed authentication configuration.

## Recovery

Restore the database, application Secret, and imported image from the backups on potatoserver.
Keep all credentials on the server. Do not generate a private copy on the Mac.
Use the [operations guide](operations.md) for the declared runtime and recovery gates.
The existing GitHub App and tunnel route remain in use.

## Operations

On potatoserver, run `make cms-logs` to read application logs.
The `cms-up` target runs a database migration job, then applies the pinned K3s declaration.
A rebuilt image requires import into K3s before deployment. The target requires the imported image reference to match the declaration.
Advance the image tag in the Makefile and manifest when the image contents change.
Build images on a workstation for Linux amd64, then transfer the archive to potatoserver.
Run `sudo bash ops/import-cms-image.sh /home/rossgrat/pages-cms-image.tar` before `make cms-up`.
The [operations guide](operations.md#cms-image-updates) contains the build, backup, and import commands.
Review database migrations before deploying an application upgrade.

On potatoserver, create a backup outside the repository:

```sh
./pages-cms/backup.sh /home/rossgrat/backups/pages-cms/manual
```

Each K3s backup contains a database dump, comparison evidence, and `resources.json`.
The resource archive includes application credentials and the token encryption key.
Keep every backup file private on potatoserver.

Before an upgrade, retain the previous image and its database backup.
If a migration changes the database, restore the matching backup before starting the previous image.
Restore into a separate database first to test the backup.
Retain the K3s claim `pages-cms/data-postgres-0` during recovery.

The dependency update addresses published [Next.js security fixes](https://github.com/advisories/GHSA-2464-fhr4-w9xw).
The application source is pinned to Pages CMS 2.1.8 with patches in `pages-cms/patch-auth.mjs` and `pages-cms/patch-validation.mjs`.
The hardened dependency set resolves the [Zod collection validation](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) and [Nodemailer email handling](https://github.com/advisories/GHSA-p6gq-j5cr-w38f) findings.
Regression tests reject oversized collections before validating every element and block file reads through raw email messages.
The November 11, 2026 production audit reports zero critical, zero high, four moderate, and four low findings.
The remaining findings involve an esbuild development-server issue and email-rendering dependencies.
This deployment does not run the esbuild development server or configure email delivery.
Review these findings when updating dependencies or enabling email features.
An audit that also includes development dependencies reports eleven moderate and four low findings, with no high or critical findings.

See the upstream [self-hosting guide](https://pagescms.org/docs/guides/installing/self-host/),
[database guide](https://pagescms.org/docs/development/database/), and
[GitHub manifest documentation](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).
