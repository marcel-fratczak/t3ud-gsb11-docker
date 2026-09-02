# T3UD-GSB11

Der **Government Site Builder 11** – das TYPO3-13-basierte CMS der
Bundesverwaltung – als Docker-Stack auf dem eigenen Notebook. Drei Befehle,
kein DDEV, kein Reverse Proxy, keine Cloud.

Entstanden als Live-Demo für einen Vortrag auf den
[TYPO3 University Days](https://t3th.org/). Basis ist die offizielle
Open-CoDE-Distribution
[itzbund/gsb-sitepackage](https://gitlab.opencode.de/bmi/government-site-builder-11).

Auf Wunsch bringt die Installation einen **Democontent** mit: eine
Beispielseite im GSB11-Farbschema mit Startseite, Programm-Timeline und
Bildergalerie – gedacht, um zu zeigen, was sich mit dem GSB11 gestalten lässt.

---

## Installation

Vorausgesetzt sind **Docker** und **Docker Compose v2**, rund 4 GB freier
Arbeitsspeicher, etwa 5 GB Plattenplatz und eine Internetverbindung (Composer
lädt die Distribution zur Installationszeit).

```bash
git clone https://github.com/marcel-fratczak/t3ud-gsb11-docker.git
```

```bash
cd t3ud-gsb11-docker
```

```bash
./scripts/setup.sh
```

Mehr ist nicht nötig. Das Skript prüft die Vorbedingungen, stellt drei Fragen,
baut die Container und installiert den GSB11 nach den offiziellen Schritten des
Sitepackage-Kickstarters. Je nach Leitung und Rechner dauert das **10 bis 20
Minuten** – der Löwenanteil davon ist `composer create-project`.

### Die drei Fragen

| Frage | Vorgabe | Bedeutung |
|-------|---------|-----------|
| Democontent mitinstallieren? | ja | Legt die T3UD-Beispielseite an. „nein" lässt die nackte GSB11-Grundinstallation stehen. |
| Host-Port für das Frontend | `8080` | Nur ändern, wenn 8080 auf dem Rechner schon belegt ist. |
| Passwort für den Administrator | – | Zugang zum Backend. Leer lassen erzeugt ein Zufallspasswort. |

Alles Weitere ist für eine Notebook-Installation eindeutig und wird deshalb
nicht abgefragt: Adresse `localhost`, Bindung an `127.0.0.1`, Datenbankname
`gsb11`, zufällige Datenbank-Passwörter. Sämtliche Werte landen in `.env`
(Rechte `600`, nicht versioniert) und lassen sich dort nachträglich ändern.

### Danach

```
Frontend : http://localhost:8080/
Backend  : http://localhost:8080/typo3   (Benutzer: admin)
```

Das Administrator-Passwort steht in `.env` unter `TYPO3_ADMIN_PASSWORD`.

---

## Democontent

Der Democontent besteht aus zwei zusätzlichen Seiten (**Programm**,
**Impressionen**), sechs Inhaltselementen auf drei Seiten, sieben Grafiken und
dem Mandanten-Stylesheet mit der GSB11-Farbpalette:

| Farbe | Wert | Verwendung |
|-------|------|------------|
| Petrol | `#007A89` | Primärfarbe, Buttons, Akzente |
| Achat | `#0B4D59` | Sekundärfarbe, Verläufe, Links |
| Anthrazit | `#333333` | Fließtext |
| Fluorit | `#66DDEC` | Hervorhebungen auf dunklem Grund |
| Jade | `#F3F7FB` | Flächen, Karten |

Primär- und Sekundärfarbe setzt das Skript in `config/sites/gsb/settings.yaml`
der Installation; von dort erzeugt `EXT:gsb_core` die Bootstrap-Variablen
`--bs-primary` und `--bs-secondary`. Alles Weitere steht in
[`demo/css/mandant.css`](demo/css/mandant.css) – genau der Datei, die die
Distribution als Anpassungspunkt für Mandanten vorsieht.

Wurde beim Setup „nein" gewählt, lässt sich der Democontent jederzeit
nachinstallieren:

```bash
./scripts/demo-content.sh
```

Das Skript ist wiederholbar: Vorhandener Democontent wird vorher entfernt,
Dubletten entstehen also nicht. Details und wie sich Texte und Bilder ersetzen
lassen: [`demo/README.md`](demo/README.md).

> **Hinweis zum Inhalt:** Das gezeigte Programm ist ein *Beispielprogramm* und
> kein offizielles Programm der TYPO3 University Days; die Abbildungen sind
> stilisierte Grafiken und zeigen keine realen Personen oder Orte. Beides ist
> auf den Seiten selbst entsprechend gekennzeichnet.

---

## Architektur

| Service | Image | Aufgabe |
|---------|-------|---------|
| `web` | eigenes Image (`nginx:stable-alpine` + `apk upgrade`) | Auslieferung des Docroot `.build/public`, FastCGI-Proxy |
| `php` | eigenes Image (`php:8.3-fpm` + GSB-Erweiterungen und Werkzeuge) | PHP-Ausführung |
| `db` | `mariadb:10.11` | Datenbank |

Der GSB11 liegt per Bind-Mount in `./app` – wie beim offiziellen DDEV-Workflow,
nur ohne DDEV. Die Datenbank liegt im Volume `db-data`.

```
Browser ──▶ 127.0.0.1:8080 ──▶ web (nginx) ──FastCGI──▶ php ──▶ db
                                    │                    │
                                    └── ./app (ro) ──────┘
```

---

## Betrieb

```bash
docker compose up -d              # starten
docker compose down               # stoppen (Daten bleiben erhalten)
docker compose logs -f php        # Logs verfolgen
docker compose exec php vendor/bin/typo3 cache:flush
```

Komplett zurücksetzen und von vorn beginnen:

```bash
docker compose down -v && rm -rf app .env
```

**Updates** der Distribution laufen manuell – `setup.sh` ist ein Erst-Setup,
kein Deployment-Pfad:

```bash
docker compose exec php composer update
docker compose exec php vendor/bin/typo3 extension:setup
docker compose exec php vendor/bin/typo3 database:updateschema
docker compose exec php vendor/bin/typo3 cache:flush
```

---

## Vor dem Vortrag

Die Installation braucht das Netz. Auf einer Konferenz ist das die
unzuverlässigste Komponente im Aufbau – deshalb einmal vorher durchspielen und
den Stack anschließend einfach stehen lassen:

```bash
./scripts/setup.sh --demo --port 8080 --admin-password 'Mein-Passwort-2026.'
```

Mit allen drei Optionen läuft das Skript ohne eine einzige Rückfrage durch.
Danach genügt am Veranstaltungsort:

```bash
docker compose up -d
```

Das startet in Sekunden und braucht **kein** Internet mehr – Images, Datenbank
und `./app` liegen dann bereits lokal. Wer die Erstinstallation trotzdem live
zeigen will, sollte vorher `docker compose build` ausführen: Dann ist wenigstens
der Image-Build erledigt und nur noch Composer auf das Netz angewiesen.

`./scripts/setup.sh --help` zeigt alle Optionen.

---

## Die Seite nach außen veröffentlichen

Standardmäßig hängt der Port an `127.0.0.1` – die Seite ist ausschließlich vom
Notebook selbst erreichbar. Für alles darüber hinaus, vom Kollegen im selben
WLAN bis zur öffentlichen Domain mit TLS und eingeschränktem Backend, gibt es
eine eigene Anleitung: **[`docs/reverse-proxy.md`](docs/reverse-proxy.md)**.

Eine Sache vorweg, weil sie regelmäßig unterschätzt wird: Docker trägt seine
iptables-Regeln **vor** denen von `ufw` oder `firewalld` ein. Eine Host-Firewall
greift bei veröffentlichten Container-Ports also nicht. Die einzige verlässliche
Grenze ist `BIND_IP` in `.env`.

---

## Härtung

- `no-new-privileges` für alle drei Container
- `web`-Container read-only, Schreibpfade als tmpfs, Code-Mount nur lesend
- Ressourcenlimits (CPU/RAM) pro Container – ein Container kann das Notebook
  nicht lahmlegen
- Sicherheits-Header in nginx (`X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`); CSP verwaltet TYPO3 v13 selbst, HSTS gehört an den Proxy
- `server_tokens off` und `expose_php Off`
- Healthchecks für alle drei Container; `web` startet erst, wenn `php` gesund ist
- Datenbank-Port nicht veröffentlicht, Zugangsdaten ausschließlich in `.env`
- `pull: true` zieht bei jedem Rebuild das aktuellste (gepatchte) Base-Image

Der `Production`-Kontext ist Standard. Wer Fehlermeldungen im Klartext sehen
will, setzt `TYPO3_CONTEXT=Development` in `.env` – für eine Vorführung auf
einer Leinwand aber besser nicht.

---

## Sicherheit und Nachvollziehbarkeit

Im Repository laufen automatisiert, jeweils **wöchentlich montags** und
zusätzlich bei jedem Push und Pull Request:

| Prüfung | Werkzeug | Verhalten |
|---------|----------|-----------|
| CVEs in den eigenen Images (`php`, `nginx`) | Trivy | Build schlägt fehl bei **behebbaren** MEDIUM/HIGH/CRITICAL |
| CVEs im `mariadb`-Image | Trivy | Warn-Annotation statt hartem Gate – das Image kommt unverändert von upstream |
| Fehlkonfigurationen in Dockerfiles und Compose | Trivy | Reporting; bewusste Ausnahmen mit Begründung in [`.trivyignore`](.trivyignore) |
| Versehentlich eingecheckte Zugangsdaten | Trivy | Build schlägt fehl |
| Base-Images und GitHub Actions | Dependabot | Wöchentliche Update-PRs |

Die Ergebnisse liegen als Artifact an jedem Lauf und – weil das Repository
öffentlich ist – zusätzlich als SARIF im Security-Tab.

**SBOM:** Für alle drei Images wird eine CycloneDX-SBOM erzeugt und nach
[`sbom/`](sbom/) zurückgeschrieben. Sie ist normalisiert
([`scripts/normalize-sbom.py`](scripts/normalize-sbom.py)): Zeitstempel,
Seriennummer, Image-Digest und Architektur-Qualifier sind entfernt, die
Komponenten deterministisch sortiert. Dadurch ändert sich die abgelegte Datei
nur, wenn sich die Software-Zusammensetzung tatsächlich ändert – nicht bei jedem
Build.

### Stand der Prüfung

Geprüft am **15.08.2026** mit Trivy (`--ignore-unfixed`, Schweregrade
MEDIUM/HIGH/CRITICAL):

| Ziel | Ergebnis |
|------|----------|
| `docker/php` (Debian 12, PHP 8.3) | 0 behebbare Funde |
| `docker/nginx` (Alpine 3.24.1) | 0 behebbare Funde |
| `mariadb:10.11` | 4 MEDIUM (Ubuntu-Pakete) + 37 in `usr/local/bin/gosu` |
| Konfiguration (Dockerfiles, Compose) | 0 nach dokumentierten Ausnahmen |
| Secret-Scan über das Repository | 0 |

Die eigenen Images sind sauber. Die MariaDB-Funde kommen unverändert aus dem
Upstream-Image und lassen sich hier nicht beheben:

- Die 4 MEDIUM betreffen `libsystemd0`/`libudev1` und werden mit dem nächsten
  Upstream-Rebuild verschwinden. `docker compose pull` holt ihn ab.
- **`gosu`** ist ein statisch gelinktes Go-Binary; die 37 Funde sind
  Go-Stdlib-CVEs in `crypto/tls`, `crypto/x509`, `net/url`, HTTP/2 und DNS.
  `gosu` liest `/etc/passwd`, ruft `setuid` und `exec` – keiner dieser
  Codepfade wird erreicht. Im Entrypoint kommt es genau einmal vor.
- Ein Wechsel auf `mariadb:11.4` hilft nicht: dort stecken dieselben
  systemd-CVEs und derselbe `gosu`-Build (geprüft am 15.08.2026).

Deshalb ist das Gate für das DB-Image bewusst weich – ein roter Build würde
hier nur unbeteiligte Änderungen blockieren, ohne dass sich etwas beheben ließe.

Die beiden akzeptierten Konfigurationsfunde stehen mit Begründung in
[`.trivyignore`](.trivyignore): `DS-0002` (kein `USER` im Dockerfile – beide
Images trennen Master und Worker, die requestverarbeitenden Prozesse laufen
bereits unprivilegiert) und `DS-0026` (Healthchecks liegen in `compose.yaml`
statt in den Dockerfiles, weil der db-Container ein unverändertes
Upstream-Image nutzt).

Selbst nachprüfen:

```bash
docker build --pull -t t3ud-gsb11-php docker/php
```

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --ignore-unfixed --severity MEDIUM,HIGH,CRITICAL t3ud-gsb11-php
```

`--pull` ist dabei wichtig: Ohne das wird ein veraltetes Base-Image gescannt,
und der Report meldet Funde, die es real längst nicht mehr gibt.

---

## Bekannte Stolpersteine

- **Port 8080 belegt.** Beim Setup einen anderen Port wählen oder
  `HTTP_PORT` in `.env` ändern und `docker compose up -d` erneut ausführen.
  Wird der Port nachträglich geändert, muss auch `FRONTEND_DOMAIN`,
  `BACKEND_DOMAIN` und `TRUSTED_HOSTS_PATTERN` mitgezogen werden.
- **HTTP 500 nach einer Änderung an `.env`.** Fast immer passt
  `TRUSTED_HOSTS_PATTERN` nicht mehr zum aufgerufenen Host. Der Wert ist ein
  regulärer Ausdruck – Punkte gehören maskiert.
- **Passwörter in `.env`.** Die Datei wird von der Shell *und* vom
  Compose-Parser gelesen, die Escapes unterschiedlich behandeln. Das Skript
  lässt deshalb nur Zeichen zu, die in beiden Parsern unproblematisch sind.
- **Kein sendmail im Container.** Ohne konfiguriertes SMTP schlagen Formulare,
  Benachrichtigungen und die Passwort-Zurücksetzung fehl. Für die lokale Demo
  ohne Belang; die `MAIL_*`-Werte in `.env` sind der Ansatzpunkt.
- **Der erste Build hängt an `pecl install`.** Kommt vor, wenn die Leitung
  zwischendurch abreißt. `./scripts/setup.sh` erneut starten – fertige Layer
  sind gecacht, der Lauf setzt dort auf.
- **GSB-Vorgaben.** Die Distribution setzt `allowedAudio/VideoDomains` auf
  `*.bund.de` und brandet das Backend mit ITZBund-Logos. Beides ist über
  `ALLOWED_MEDIA_DOMAINS`, `BACKEND_LOGIN_FOOTNOTE` und
  `BACKEND_LOGIN_LOGO_ALT` in `.env` anpassbar.

---

## Lizenz

GSB 11 und Sitepackage: [GPL-3.0-or-later](https://spdx.org/licenses/GPL-3.0-or-later.html).
Die Container-Konfiguration und der Democontent dieses Repositorys ebenfalls
GPL-3.0-or-later, siehe [`LICENSE`](LICENSE).

Dieses Repository ist ein privates Demonstrationsprojekt. Es ist weder ein
offizielles Angebot des ITZBund noch der TYPO3 University Days.

---

## English summary

Container setup that runs **Government Site Builder 11** – the German federal
administration's TYPO3 13 based CMS – as a local Docker stack on a laptop,
built as a live demo for a talk at the TYPO3 University Days. It is based on
the official Open CoDE distribution.

Clone the repository, `cd` into it and run `./scripts/setup.sh`. The script
asks three questions (install demo content, host port, administrator password),
defaults everything else to a local install on `127.0.0.1:8080`, writes `.env`
and installs GSB11 into `./app` via Composer. All three answers can be passed
as options (`--demo`, `--port`, `--admin-password`) for a fully non-interactive
run — which is also what the CI smoke test exercises.

Optionally it installs a **demo site** in the official GSB11 colour palette
(two extra pages, six content elements, seven illustrations and the tenant
stylesheet). The demo programme is fictional and the illustrations are
stylised graphics; both are labelled as such on the pages themselves.

By default the stack binds to `127.0.0.1` and is reachable from the laptop
only. See [`docs/reverse-proxy.md`](docs/reverse-proxy.md) before exposing it —
Docker's iptables rules bypass host firewalls, so `BIND_IP` is the actual
boundary.

Weekly Trivy scans (images, configuration, secrets), weekly Dependabot updates
and a normalised CycloneDX SBOM per image run in GitHub Actions. Prompts and
documentation are in German; configuration reference: [`.env.example`](.env.example).
