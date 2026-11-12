# Pages CMS

Edit the blog at `https://cms.grattafiori.dev` using the GitHub account `rossgrat`.
GitHub is the source of posts and images; PostgreSQL stores sessions, credentials, and repository cache.
The [blog publishing guide](https://github.com/rossgrat/rossgrat.github.io/blob/main/docs/publishing.md) covers writing.

## Access and deployment

The CMS is public through Cloudflare Tunnel, without a separate Tailscale or Cloudflare Access login.
The application accepts only GitHub user ID `69823943`, configured by `ALLOWED_GITHUB_USER_ID`.
A missing owner ID denies sign-in. Email sign-in is disabled.
The GitHub App is installed only on the blog repository, with Contents/Actions write access and read access to checks, statuses, and metadata.
Administration permission is disabled.

The [K3s declaration](../k3s/pages-cms.yaml) pins the application and database images.
[Dockerfile](../pages-cms/Dockerfile) and the lockfile pin Pages CMS, Node, and patched dependencies.
The build tests owner restrictions, token renewal, forms, and dependency regressions.
Application access controls do not protect a stolen GitHub account or CMS session; keep both secure.

Build on a workstation for Linux amd64 and import the archive into K3s before deployment.
See [CMS update commands](operations.md#cms-updates) for image tags, database backup, import, and `make cms-up`.
The deployment target runs a migration Job before applying the application declaration.
On potatoserver, `make cms-logs` reads application logs.

## Back up and recover

Restore the database, application Secret, and imported image from protected backups on potatoserver.
Keep credentials on that server; do not create a private copy on the Mac.
Retain claim `pages-cms/data-postgres-0` and the existing GitHub App and tunnel credentials.
Use a new backup directory for each manual database backup, as shown in [operations](operations.md#backups).

Backups include the token-encryption key and application credentials. Keep every backup file private.
Before upgrading, retain the previous image and its matching database backup.
Test restoration in a separate database first.
If a migration changes the schema, restore the matching database backup before starting the previous image.

The source patches address the recorded [Next.js](https://github.com/advisories/GHSA-2464-fhr4-w9xw), [Zod](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5), and [Nodemailer](https://github.com/advisories/GHSA-p6gq-j5cr-w38f) findings.
Keep the vendored shadcn stylesheet and its license when maintaining the build.
