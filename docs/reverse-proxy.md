# Die Seite nach außen veröffentlichen

Standardmäßig ist der Stack **nur auf dem Notebook selbst** erreichbar: Der Port
hängt an `127.0.0.1`. Für den Vortrag ist das genau richtig. Dieses Dokument
beschreibt die drei Wege, die Seite darüber hinaus verfügbar zu machen – vom
Kollegen im selben WLAN bis zur öffentlichen Domain mit TLS.

> **Zuerst das Wichtigste:** Docker trägt seine iptables-Regeln **vor** denen von
> `ufw` oder `firewalld` ein. Eine Host-Firewall greift bei veröffentlichten
> Container-Ports also **nicht**. Die einzige verlässliche Grenze ist
> `BIND_IP` in `.env`. Wer sie auf `0.0.0.0` stellt, veröffentlicht den Stack
> ungeschützt auf allen Schnittstellen – inklusive `/typo3`.

Nach jeder Änderung an `.env`:

```bash
docker compose up -d
```

---

## Fall 1 – Im eigenen Netz sichtbar machen (LAN/WLAN)

Der schnellste Weg, damit jemand im selben Netz mitschauen kann. Kein TLS,
keine Domain, kein Proxy.

**1. Eigene IP-Adresse ermitteln**

```bash
ipconfig getifaddr en0
```

Unter Linux: `ip -4 -o addr show | awk '{print $2, $4}'`.

**2. `.env` anpassen** – angenommen, die Adresse ist `192.168.1.42`:

```ini
BIND_IP=192.168.1.42
FRONTEND_DOMAIN=192.168.1.42:8080
BACKEND_DOMAIN=192.168.1.42:8080
TRUSTED_HOSTS_PATTERN='192\.168\.1\.42:8080'
```

`BIND_IP` auf die konkrete Adresse statt auf `0.0.0.0`: Damit hängt der Stack
nur an dieser einen Schnittstelle. Steckt das Notebook später an einem anderen
Netz, ist der Port dort nicht automatisch offen.

`TRUSTED_HOSTS_PATTERN` ist ein regulärer Ausdruck gegen den `Host`-Header –
die Punkte gehören deshalb maskiert. Passt der Wert nicht, antwortet TYPO3 mit
HTTP 500 statt der Seite.

**3. Grenzen dieses Wegs**

Ohne TLS geht das Backend-Passwort im Klartext über das Netz. Für eine
Vorführung im Konferenz-WLAN gilt: entweder das Backend nicht benutzen oder
Fall 3 wählen. Nach dem Vortrag `BIND_IP=127.0.0.1` zurücksetzen.

---

## Fall 2 – Reverse Proxy auf demselben Rechner

Ein lokaler Proxy (Caddy, nginx, Traefik) terminiert TLS und reicht an den
Stack weiter. Der Container-Port bleibt auf `127.0.0.1` – nur der Proxy kommt
daran.

**`.env`**

```ini
BIND_IP=127.0.0.1
HTTP_PORT=8080
GSB_SCHEME=https
FRONTEND_DOMAIN=gsb11.example.org
BACKEND_DOMAIN=gsb11.example.org
TRUSTED_HOSTS_PATTERN='gsb11\.example\.org'

# Adresse, die beim Stack als REMOTE_ADDR ankommt. Bei einem Proxy auf
# demselben Host ist das die Gateway-Adresse des Docker-Bridge-Netzes.
REVERSE_PROXY_IP=172.17.0.1
REVERSE_PROXY_SSL=*
```

Die tatsächliche Gateway-Adresse ermitteln:

```bash
docker network inspect t3ud-gsb11_gsb --format '{{(index .IPAM.Config 0).Gateway}}'
```

`REVERSE_PROXY_IP` ist der Punkt, an dem die meisten Setups scheitern: TYPO3
wertet die weitergereichten `X-Forwarded-`-Header **nur** aus, wenn die
Absenderadresse zu diesem Wert passt. Stimmt er nicht, entstehen `http://`-Links
in einer `https://`-Seite und im Backend Redirect-Schleifen.

### Caddy

Caddy holt sich das Zertifikat selbst und setzt die `X-Forwarded-`-Header
automatisch:

```caddyfile
gsb11.example.org {
    reverse_proxy 127.0.0.1:8080
}
```

### nginx

```nginx
server {
    listen 443 ssl http2;
    server_name gsb11.example.org;

    ssl_certificate     /etc/letsencrypt/live/gsb11.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gsb11.example.org/privkey.pem;

    # HSTS gehört an den Edge – der Container setzt es bewusst nicht.
    add_header Strict-Transport-Security "max-age=31536000" always;

    # 32 MB: dieselbe Grenze wie im Container (nginx client_max_body_size
    # und PHP upload_max_filesize). Ein kleinerer Wert hier bricht Uploads.
    client_max_body_size 32m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 240s;
    }
}
```

`proxy_set_header Host $host` ist Pflicht: Ohne ihn kommt `127.0.0.1:8080` als
Host an, und das passt nicht zu `TRUSTED_HOSTS_PATTERN`.

---

## Fall 3 – Reverse Proxy auf einem anderen Host

Der Proxy läuft auf einer öffentlich erreichbaren Maschine, der GSB11 auf dem
Notebook – verbunden über VPN oder ein Overlay-Netz (WireGuard, Tailscale,
NetBird). Dann darf der Port weder auf `127.0.0.1` (der Proxy käme nicht dran)
noch auf `0.0.0.0` liegen, sondern gehört an die VPN-Adresse des Notebooks:

```ini
BIND_IP=100.64.0.7          # VPN-Adresse dieses Rechners
FRONTEND_DOMAIN=gsb11.example.org
BACKEND_DOMAIN=gsb11.example.org
TRUSTED_HOSTS_PATTERN='gsb11\.example\.org'
GSB_SCHEME=https
REVERSE_PROXY_IP=100.64.0.1 # VPN-Adresse des Proxy-Hosts
REVERSE_PROXY_SSL=*
```

Auf dem Proxy-Host greifen Docker-Labels nicht, weil der GSB11 dort nicht
läuft. Bei Traefik ist deshalb der File-Provider der richtige Weg:

```yaml
# /etc/traefik/dynamic/gsb11.yml
http:
  routers:
    gsb11:
      rule: "Host(`gsb11.example.org`)"
      entryPoints: [websecure]
      service: gsb11
      tls:
        certResolver: le
      middlewares: [gsb11-hsts]

  services:
    gsb11:
      loadBalancer:
        servers:
          - url: "http://100.64.0.7:8080"

  middlewares:
    # Nur HSTS gehört an den Edge – X-Content-Type-Options, X-Frame-Options
    # und Referrer-Policy setzt der nginx-Container bereits selbst.
    gsb11-hsts:
      headers:
        stsSeconds: 31536000
```

Drei Dinge sind bei Traefik bewusst *nicht* konfiguriert, weil sie schon passen:
`passHostHeader` ist per Default `true`, `X-Forwarded-Proto`/`-For` setzt
Traefik automatisch, und ein Default-Limit für die Body-Größe gibt es nicht.

Anzupassen ist genau ein Wert in der statischen Konfiguration: Der
`readTimeout` von 60 s deckt das Lesen des kompletten Requests inklusive Body ab
und reicht für einen 32-MB-Upload durch einen VPN-Tunnel nicht.

```yaml
# traefik.yml
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 240s
```

### Das Backend zusätzlich einschränken

Das Frontend öffentlich, `/typo3` nur aus dem eigenen Netz – als zweiter Router
mit höherer Priorität:

```yaml
    gsb11-backend:
      rule: "Host(`gsb11.example.org`) && PathPrefix(`/typo3`)"
      priority: 100
      entryPoints: [websecure]
      service: gsb11
      tls:
        certResolver: le
      middlewares: [gsb11-hsts, gsb11-allowlist]

  middlewares:
    gsb11-allowlist:
      ipAllowList:
        sourceRange:
          - 100.64.0.0/10
```

---

## Checkliste

| Prüfung | Kommando |
|---------|----------|
| Port hängt an der erwarteten Adresse | `docker compose ps` |
| Stack antwortet direkt | `curl -i http://<BIND_IP>:8080/healthz` |
| Proxy reicht korrekt durch | `curl -I https://<domain>/` |
| TYPO3 erkennt HTTPS | Im Quelltext der Seite dürfen keine `http://<domain>`-Links stehen |
| Backend erreichbar | `https://<domain>/typo3` ohne Redirect-Schleife |

Häufigste Ursachen, wenn es klemmt:

- **HTTP 500 statt Seite** → `TRUSTED_HOSTS_PATTERN` passt nicht zum Host-Header.
- **Mixed Content / `http://`-Links** → `REVERSE_PROXY_IP` stimmt nicht mit der
  Adresse überein, von der der Proxy kommt.
- **Redirect-Schleife im Backend** → derselbe Grund, zusätzlich fehlt oft
  `REVERSE_PROXY_SSL=*`.
- **Upload bricht ab** → Body-Limit oder Timeout des Proxy kleiner als die
  32 MB bzw. 240 s des Containers.

---

## Zurück auf lokal

Nach dem Vortrag:

```ini
BIND_IP=127.0.0.1
GSB_SCHEME=http
FRONTEND_DOMAIN=localhost:8080
BACKEND_DOMAIN=localhost:8080
TRUSTED_HOSTS_PATTERN='(localhost|127\.0\.0\.1):8080'
REVERSE_PROXY_IP=
REVERSE_PROXY_SSL=
```

```bash
docker compose up -d
```
