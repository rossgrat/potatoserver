# Pages CMS

Pages CMS edits the blog repository at `https://cms.grattafiori.dev`.
The existing Cloudflare Tunnel forwards this hostname to `127.0.0.1:3030` on potatoserver.
Pages CMS requires GitHub sign-in and repository write access for editing.
The GitHub App is installed only on `rossgrat/rossgrat.github.io`.

The application and its PostgreSQL database use separate Docker containers.
PostgreSQL stores login sessions, credentials, and cached repository data.
GitHub retains the authoritative posts and images.
The database does not publish a host port.

The image pins Pages CMS 2.1.8, Node 24.22.2, and their source or image digests.
PostgreSQL uses version 18.6 with a pinned digest.
The build uses the upstream dependency lockfile.
Database migrations run in a separate container before the application starts.

## Initial setup

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

See the upstream [self-hosting guide](https://pagescms.org/docs/guides/installing/self-host/),
[database guide](https://pagescms.org/docs/development/database/), and
[GitHub manifest documentation](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).
