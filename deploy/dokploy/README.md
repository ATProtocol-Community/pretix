# deploy/dokploy — pretix for tickets.atmosphereconf.org

This directory holds the Dokploy (Docker Compose) deployment for the ATmosphere
Conference ticket shop. It is not upstream pretix; it belongs to our fork's
`cic` branch.

## How it fits together

```
push to `cic` (this fork)
        │
        ├─ .github/workflows/build-publish.yaml  →  ghcr.io/atprotocol-community/pretix:cic-<sha12> (+ :cic)
        │
        └─ Dokploy (project "atmosphereconf pretix") redeploys compose.yml
                      └─ pulls the prebuilt image (no pretix build on the VM)
```

- **Branch:** `cic`, tracking upstream tag `v2026.9.0`. `master` holds upstream.
- **Image:** built from this fork's **own root `Dockerfile`** (nginx + gunicorn +
  celery; static assets via `make production`). Dokploy never builds it — the VM
  is small and builds take ~10–20 minutes.
- **Projects/services:** Dokploy project `atmosphereconf pretix`
  (projectId `TlqVIxF1Jddhz2r0PdtAS`), environment `production`
  (`GpFlN4v8rb2mfRS4MoRuL`), compose service `pretix`,
  `composePath: ./deploy/dokploy/compose.yml`.

## Fork changes vs upstream

1. `deployment/docker/pretix.bash` — renders `/etc/pretix/pretix.cfg` from
   `PRETIX_*` environment variables when `PRETIX_CONFIG_FROM_ENV=yes` (no-op
   otherwise). Lets secrets live in the orchestrator instead of a bind-mounted
   config file.
2. `Dockerfile` — one line, `chown pretixuser:pretixuser /etc/pretix`, so the
   entrypoint can write that config as the unprivileged user.
3. `deploy/dokploy/` — this stack.
4. `.github/workflows/build-publish.yaml` — GHCR build/publish (upstream builds
   their official images out-of-tree, so there is nothing to reuse).

Keep these as small and rebase-friendly as possible: upstream tags move monthly
(`v2026.10.0`, …), and we want `git rebase` onto the new tag to stay boring.

## Environment

See the header comment of `compose.yml` for the full list. Secrets (database
password, `PRETIX_SECRET`, SMTP credentials, redis password) are set in the
Dokploy UI and mirrored into the atgeo-infra ansible vault for recovery — per
the CIC wiki's credential pattern ([CIC_Wiki_Conventions](https://cic.robot.wtf/CIC_Wiki_Conventions)).

## Operating notes

- **Upgrade:** bump `PRETIX_IMAGE_TAG` in Dokploy (pin the `cic-<sha12>` of the
  build you want), redeploy. `AUTOMIGRATE=yes` runs migrations at container
  start. **Take a database + `/data` backup first** — pretix requires it.
- **Backups:** `pretix-db` volume (`pg_dump`) and `pretix-data` (`/data`: media,
  invoices/PDFs).
- **Scheduled tasks:** the `cron` service runs `pretix cron` (runperiodic) every
  60s, which is what the pretix docs require of a systemd timer in a
  non-container install.
- **Domains:** configured in the Dokploy UI (Domains tab) — `tickets.atmosphereconf.org`
  → service `pretix`, container port `80`, Let's Encrypt. Compose domain changes
  need a redeploy (Traefik labels, unlike Applications which hot-reload).

Deployment plan and decisions: https://cic.robot.wtf/Pretix_Deployment_Plan
