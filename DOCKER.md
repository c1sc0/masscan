# Running masscan in Docker

A multi-stage [`Dockerfile`](Dockerfile) builds masscan and ships a minimal
runtime image (~78 MB) with `libpcap` installed.

> **Why the extra capabilities?** masscan uses its own custom TCP/IP stack and
> raw sockets, bypassing the kernel network stack. It needs `NET_RAW` +
> `NET_ADMIN`, and host networking so it can see the real interface and routes
> (bridge NAT would drop the replies).

## Build

```sh
docker build -t masscan .
```

## Run with `docker`

```sh
# Version
docker run --rm masscan --version

# Self-test (no privileges needed)
docker run --rm masscan --selftest

# Scan port 80 across a /24
docker run --rm --cap-add=NET_RAW --cap-add=NET_ADMIN --network host \
    masscan -p80 10.0.0.0/24

# Multiple ports, JSON output to a mounted dir
docker run --rm --cap-add=NET_RAW --cap-add=NET_ADMIN --network host \
    -v "$PWD/output:/output" \
    masscan -p80,443 -oJ /output/scan.json 10.0.0.0/24
```

## Run with `docker compose`

[`docker-compose.yml`](docker-compose.yml) presets the capabilities, host
networking, and an `./output` volume — just pass scan args:

```sh
# Version
docker compose run --rm masscan --version

# Scan ports 80 and 443, JSON results to ./output/scan.json
docker compose run --rm masscan -p80,443 -oJ /output/scan.json 10.0.0.0/24
```

The default `command` is `--help`; any args you pass override it.

## Port syntax (`-p`)

masscan borrows nmap's port syntax:

| Flag         | Meaning                |
|--------------|------------------------|
| `-p80`       | TCP port 80            |
| `-p80,443`   | ports 80 and 443       |
| `-p0-65535`  | full TCP range         |
| `-pU:53`     | UDP port 53            |

## TLS SNI (`--ssl-sni`) — origin-exposure audit

By default masscan's SSL ClientHello sends no SNI, so a multi-vhost origin
returns its *default* certificate. `--ssl-sni <domain>` adds a `server_name`
extension to the ClientHello so the origin serves that vhost's cert — the way
to confirm a Cloudflare origin answers for your domain directly on its raw IP.

The SNI ClientHello is built once at startup, so it adds no per-packet cost
to the scan. `--ssl-sni` implies `--banners`.

```sh
# Sweep an origin range, grab the cert each host presents for your domain
docker run --rm --cap-add=NET_RAW --cap-add=NET_ADMIN --network host \
    masscan:local -p443 --ssl-sni torrentek.org -oJ /output/origin-audit.json \
    87.236.16.0/24
```

If a host returns *your* certificate, the origin is reachable outside
Cloudflare — lock inbound 443 to Cloudflare's IP ranges.

Aliases: `--sni`, `--tls-sni`.

### Flagging matches (`--sni-match-file`)

When `--ssl-sni` is set, any SSL banner whose cert names contain the requested
hostname is **highlighted** on the console (`>>> SNI MATCH ...`). Add
`--sni-match-file <path>` to also collect matches to a file, one
`ip:port cert-summary` line per host — ready to feed a firewall script.

```sh
docker run --rm --cap-add=NET_RAW --cap-add=NET_ADMIN --network host \
    -v "$PWD/output:/output" \
    masscan:local -p443 --ssl-sni torrentek.org \
    --sni-match-file /output/exposed-origins.txt \
    87.236.16.0/24
```

A host serving some *other* default cert (SNI didn't match a vhost) is not
flagged — only a cert carrying your domain counts as a hit.

Aliases: `--sni-match`, `--match-file`.
