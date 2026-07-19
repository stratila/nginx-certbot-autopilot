# nginx-certbot-autopilot

A self-driving HTTPS reverse proxy: nginx + Let's Encrypt (certbot) in containers.
Add a domain, start the stack, and certificates are issued and renewed
automatically — no manual certbot runs, no restarts to pick up new certs.

Run it as-is with a container compose tool (`podman-compose up -d` or
`docker compose up -d`), or use it as a working example to write your own
[quadlets](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
from — the containers, volumes, and ordering are all in `container-compose.yml`.

## How it works

Three services, one shared `./data/certbot` tree:

1. **cert-bootstrap** (one-shot) — generates a self-signed placeholder cert for
   every domain in `DOMAINS` that certbot doesn't manage yet. Without it nginx
   would refuse to start on a brand-new domain (missing cert files).
2. **nginx** — serves the domains from `nginx/conf.d/*.conf` and the ACME
   webroot challenge. A small watcher (`nginx/40-reload-watcher.sh`) polls a
   flag file and hot-reloads nginx whenever certbot installs a new cert.
3. **certbot** — waits for nginx, issues a real certificate for each domain
   (replacing the placeholder), then renews on a 12h loop. Flipping `STAGING`
   later forces a reissue against the right ACME server automatically.

## Quick start

1. Set your domains in `domains.env` (comma-delimited, no spaces):

   ```
   DOMAINS=app.example.com,api.example.com
   STAGING=1
   ```

2. Create one `nginx/conf.d/<domain>.conf` per domain from the template
   `nginx/conf.d.sample/sample.domain.example.conf` — replace
   `sample.domain.example` and fill in the upstream `<host>:<port>` in
   `proxy_pass`. (With Claude Code, `/new-domain <domain> <host> <port>` does
   both this and step 1.)

3. Point DNS at the server and make ports 80/443 reach the stack. The compose
   file publishes rootless-friendly ports `8080:80` and `8443:443`, so either
   redirect 80→8080 and 443→8443 on the host/router, or change the mapping.

4. Start it:

   ```bash
   podman-compose up -d    # or: docker compose up -d
   ```

5. Once staging issuance works, set `STAGING=0` in `domains.env` and run
   `podman-compose up -d` again for trusted certificates.

## Notes

- `DOMAINS` is read only at container start — after editing `domains.env` or
  adding a conf, re-run `podman-compose up -d`.
- Keep `DOMAINS` and `nginx/conf.d/*.conf` in sync: a domain without a server
  block breaks its challenge; a server block without a `DOMAINS` entry leaves
  nginx without a cert to load.
- Certificates and ACME account state live in `data/certbot/conf` on the host,
  so they survive container re-creation.
- Upstream on the host via `host.containers.internal`? With rootless podman's
  pasta networking the container can't reach host loopback — see the caveats at
  the end of `.claude/skills/new-domain/SKILL.md` for the two fixes.
