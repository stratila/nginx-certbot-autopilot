---
name: new-domain
description: Add a new domain to the nginx/certbot setup - generates nginx/conf.d/<domain>.conf from the sample template and registers the domain in DOMAINS in domains.env. Use when the user asks to add, create, or register a new domain/site.
argument-hint: <domain> <host> <port>
---

Add a new proxied domain to this project. Three inputs are required:

- **domain** — the public server name (e.g. `app.example.com`)
- **host** — the upstream host that `proxy_pass` should target
- **port** — the upstream port that `proxy_pass` should target

If any of the three is missing from the arguments, ask the user for it before doing anything.

## Validation (do this first)

1. Domain must look like a hostname: lowercase letters, digits, dots, hyphens (e.g. `sub.example.com`). No scheme, no slashes, no wildcards.
2. Port must be an integer 1–65535.
3. `nginx/conf.d/<domain>.conf` must not already exist and the domain must not already be listed in `DOMAINS` in `domains.env`. If either is true, stop and tell the user the domain is already configured.

## Step 1 — generate the nginx config

Create `nginx/conf.d/<domain>.conf` from the template `nginx/conf.d.sample/sample.domain.example.conf`:

```bash
mkdir -p nginx/conf.d
sed -e "s/sample\.domain\.example/<domain>/g" \
    -e "s/<host>/<host value>/" \
    -e "s/<port>/<port value>/" \
    nginx/conf.d.sample/sample.domain.example.conf > "nginx/conf.d/<domain>.conf"
```

This replaces every occurrence of `sample.domain.example` (the header comment, both `server_name` directives, and the `ssl_certificate*` paths under `/etc/letsencrypt/live/<domain>/`), and fills `<host>` and `<port>` in the `proxy_pass` line.

## Step 2 — register the domain in domains.env

Edit the `DOMAINS=` line in `domains.env` (comma-delimited list, no spaces):

- If `DOMAINS` still contains the placeholder `sample.domain.example` and `nginx/conf.d/sample.domain.example.conf` does not exist, **replace** the placeholder with the new domain.
- Otherwise **append** `,<domain>` to the existing list.

Do not touch any other line in `domains.env` (in particular `STAGING`).

## Step 3 — verify and report

1. Show the user the generated `nginx/conf.d/<domain>.conf` — confirm no `<host>`/`<port>` placeholders or `sample.domain.example` remain in it.
2. Show the updated `DOMAINS=` line.
3. Remind the user of what happens next (do not run these steps yourself unless asked):
   - DNS for the domain must point at this server before certbot can issue a real cert.
   - `DOMAINS` is read from `domains.env` only at container start (`env_file`), so a running stack must be restarted to pick the new domain up: `podman-compose up -d` (or the docker equivalent) re-runs `cert-bootstrap` to create the self-signed placeholder cert — without it nginx refuses to load the new conf — and restarts certbot, which then issues the real cert and triggers an nginx reload via the reload watcher.
   - If `STAGING=1` in `domains.env`, the cert will come from the Let's Encrypt staging CA (untrusted, for testing).
   - If the upstream host is `host.containers.internal` (a service running on the host): with pasta networking (rootless podman default) the container cannot reach services bound to the host's loopback. Two ways to fix it:

     **Option A — bind the service to `0.0.0.0`**, then close the port in the firewall so it is not reachable from outside (only nginx should be publicly exposed):

     ```bash
     # bad  — unreachable from the container
     uvicorn app:app --host 127.0.0.1 --port <port>
     # good — reachable via host.containers.internal
     uvicorn app:app --host 0.0.0.0 --port <port>

     sudo ufw deny <port>/tcp   # or the firewalld equivalent
     ```

     **Option B — keep the service on `127.0.0.1`** and have pasta map the host loopback into the container, in `~/.config/containers/containers.conf`:

     ```toml
     [network]
     pasta_options = ["--map-host-loopback", "169.254.1.2"]
     ```

     `169.254.1.2` is the address `host.containers.internal` resolves to, so the generated `proxy_pass` keeps working unchanged. Containers must be recreated (`podman-compose down && podman-compose up -d`) for the new pasta options to take effect.