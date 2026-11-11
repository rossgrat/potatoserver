# Pages CMS

Pages CMS edits the blog repository at `https://cms.grattafiori.dev`.
The existing Cloudflare Tunnel forwards this hostname to `127.0.0.1:3030` on potatoserver.
Only the GitHub account `rossgrat` can sign in to this CMS.
The authentication callback accepts only GitHub user ID `69823943`, as set by `ALLOWED_GITHUB_USER_ID`.
A missing owner ID denies sign-in. Email sign-in is disabled.
GitHub repository permissions still control edits.
The GitHub App is installed only on `rossgrat/rossgrat.github.io`.

The application and its PostgreSQL database use separate Docker containers.
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
Database migrations run in a separate container before the application starts.

## Security boundary

The CMS is public over HTTPS through Cloudflare Tunnel.
It does not require Tailscale or a separate Cloudflare Access login.
The owner restriction runs in the application after GitHub identifies the account.

Session cookies use Secure, HttpOnly, and SameSite=Lax.
These attributes restrict cookie transport, script access, and cross-site use.
The app rejects cross-site authentication requests and invalid webhook signatures.
The application runs as the non-root Node user.
Its host port binds only to the local loopback address.

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
Unauthenticated content requests returned 401, and email-code login endpoints returned 404.
Password login was disabled in the deployed authentication configuration.

## Initial setup

Install [Docker Buildx 0.38.2](https://github.com/docker/buildx/releases/tag/v0.38.2) on potatoserver before building the image.
The installed plugin lives at `/home/rossgrat/.docker/cli-plugins/docker-buildx`.

On the laptop, generate `pages-cms/.env` with a database password, a session secret, and a 32-byte base64 encryption key.
Use `pages-cms/.env.example` for the variable names.
Keep the file out of Git and set its permissions to `600`.

From the infrastructure repository, run:

```sh
./pages-cms/setup-github-app.sh
```

Open the printed localhost URL in the same laptop browser.
Create the app, then install it only on the blog repository.
The helper saves credentials directly to `.env`.
It corrects the upstream helper's webhook-secret handling and email permission name for GitHub's registration form.

Copy `.env` to `/home/rossgrat/repos/network/pages-cms/.env` on potatoserver through SSH.
Keep its permissions at `600`.
From `/home/rossgrat/repos/network` on potatoserver, run:

```sh
make cms-build cms-up
```

After the application responds locally, add the DNS record and tunnel route on potatoserver:

```sh
cloudflared tunnel route dns potatoserver cms.grattafiori.dev
sudo ./pages-cms/install-tunnel-route.sh
```

The route script saves the old tunnel configuration and restores it if the tunnel fails to become ready.
GitHub sends signed notifications to `/api/webhook/github`.
The handler rejects invalid signatures.

## Operations

From the infrastructure repository on the laptop, run `make cms-deploy` to back up and update only the CMS.
On potatoserver, run `make cms-logs` to read application logs.
The `cms-up` target runs migrations before starting the application.
Do not use the general `make deploy` target for CMS updates.

On potatoserver, create a backup outside the repository:

```sh
./pages-cms/backup.sh /home/rossgrat/backups/pages-cms/manual
```

Each backup contains `database.dump` and `app.env`.
Keep both files private because they include authentication data.
The encryption key in `app.env` is required to read stored encrypted tokens.

Before an upgrade, retain the previous image and its database backup.
If a migration changes the database, restore the matching backup before starting the previous image.
Restore into a separate database first to test the backup.
Never remove the `pages-cms_postgres_data` volume during routine updates.

The dependency update addresses published [Next.js security fixes](https://github.com/advisories/GHSA-2464-fhr4-w9xw).
The application source is pinned to Pages CMS 2.1.8 with patches in `pages-cms/patch-auth.mjs` and `pages-cms/patch-validation.mjs`.
The hardened dependency set resolves the [Zod collection validation](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) and [Nodemailer email handling](https://github.com/advisories/GHSA-p6gq-j5cr-w38f) findings.
Regression tests reject oversized collections before validating every element and block file reads through raw email messages.
The November 11, 2026 production audit reports zero critical, zero high, four moderate, and four low findings.
The remaining findings involve an esbuild development-server issue and email-rendering dependencies.
This deployment does not run the esbuild development server or configure email delivery.
Review these findings when updating dependencies or enabling email features.

See the upstream [self-hosting guide](https://pagescms.org/docs/guides/installing/self-host/),
[database guide](https://pagescms.org/docs/development/database/), and
[GitHub manifest documentation](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).
