# T3UD-GSB11 – Projektkontext

Government Site Builder 11 (TYPO3 13.4 LTS) als lokaler Docker-Stack, gebaut
als Live-Demo für einen Vortrag auf den TYPO3 University Days.

## Stack

- **Basis:** `itzbund/gsb-sitepackage` von Open CoDE, per
  `composer create-project` zur Installationszeit nach `./app` geholt.
  `./app` ist nicht versioniert.
- **Container:** `web` (nginx:stable-alpine), `php` (php:8.3-fpm-bookworm),
  `db` (mariadb:10.11). Compose-Projektname `t3ud-gsb11`.
- **Docroot:** `app/.build/public` – Composer-Mode, nicht `public/`.
- **Skripte:** Bash, kompatibel zu macOS-Bash 3.2 (kein `mapfile`, keine
  assoziativen Arrays).

## Wichtige Eigenheiten der Distribution

- **Das Projekt-Root *ist* die Sitepackage-Extension** (`gsb_sitepackage`).
  Ihre Assets liegen unter `app/Resources/Public/` und hängen als Symlink
  im Docroot unter `_assets/6666cd76f96956469e7be39d750cc7d9/`.
  Eine Datei dort zu überschreiben wirkt sofort, ohne Rebuild.
- **Anpassungspunkt für Mandanten** ist
  `Resources/Public/StyleSheets/mandant.css` – Verzeichnis mit **großem S**,
  eingebunden über `Configuration/TypoScript/setup.typoscript`.
- **Primär-/Sekundärfarbe gehören nicht ins Stylesheet.** `EXT:gsb_core`
  erzeugt `--bs-primary`/`--bs-secondary` als Inline-Style aus
  `config/sites/gsb/settings.yaml`
  (`colors.colorGeneral.gsb-color-primary` usw.).
- **Grundinhalte** kommen aus `.ddev/initial-setup/mysql-db.sql`. Danach ist
  `sys_template.include_static_file` auf
  `EXT:gsb_sitepackage/Configuration/TypoScript/` zu setzen, sonst rendert das
  Frontend ohne Layout.
- **colPos 0 = `top-container`** (volle Breite), **colPos 1 = Inhaltsspalte**.
  Der Democontent nutzt colPos 0.
- **Nach dem Setup `chown -R www-data:www-data`** im php-Container. Das Setup
  läuft als root, php-fpm bedient Requests als `www-data` und muss `var/`,
  `config/system` und `fileadmin` schreiben können – sonst HTTP 500 auf Linux.

## Democontent

- Quelle: `demo/` (HTML-Fragmente, `mandant.css`, Grafiken).
- Import: `scripts/demo-content.sh`, idempotent. Marker:
  `tt_content.rowDescription = 'T3UD-Democontent'` und die Slugs
  `/programm`, `/impressionen`.
- Inhaltselemente sind CType `html`; die Bilder sind **keine** FAL-Referenzen,
  sondern liegen als Dateien unter `fileadmin/user_upload/t3ud/`.
- HTML wird per `sed`-Escaping (Backslash zuerst, dann Hochkomma) in ein
  SQL-String-Literal geschrieben. Wer Inhalte ergänzt: beides bleibt maskiert,
  Backticks und `$` sind unkritisch, weil kein Shell-Parser darüber läuft.

## Inhaltliche Leitplanken

Das Repository ist öffentlich und bezieht sich auf eine reale Veranstaltung:

- Kein Personenbezug im Content, keine echten Namen, keine privaten Domains.
- Das Programm ist **erfunden** und muss als Beispielprogramm gekennzeichnet
  bleiben (Hinweisbox auf `/programm`, Link auf t3th.org).
- Die Abbildungen sind stilisierte Grafiken und müssen als solche
  gekennzeichnet bleiben (Hinweisbox auf `/impressionen`).
- Nicht als offizielles Angebot des ITZBund oder der T3UD auftreten.

## CI

- `security.yml`: Trivy (Images, Config, Secrets) + CycloneDX-SBOM,
  wöchentlich montags 06:00 UTC, zusätzlich bei Push/PR.
  Hartes Gate nur für die **eigenen** Images und nur bei **behebbaren**
  MEDIUM/HIGH/CRITICAL; `mariadb` erzeugt nur eine Warn-Annotation, weil das
  Image unverändert von upstream kommt.
- `smoke.yml`: installiert den Stack nicht-interaktiv inklusive Democontent
  und prüft Frontend, Backend, beide Demoseiten, die gerenderten Sektionen und
  die Idempotenz des Importers.
- SBOM wird über `scripts/normalize-sbom.py` normalisiert, bevor sie
  zurückcommittet wird – sonst rauscht jeder Build durch `sbom/`.
- `.trivyignore` enthält `DS-0002` (kein `USER` im Dockerfile) mit Begründung.

## Stolpersteine, die schon Zeit gekostet haben

- `pecl install` im PHP-Build bricht bei wackliger Leitung ab. Der Fehler sieht
  nach einem Konfigurationsproblem aus, ist aber transient – einfach erneut
  bauen, gecachte Layer bleiben erhalten.
- `TRUSTED_HOSTS_PATTERN` ist ein regulärer Ausdruck gegen den Host-Header.
  Passt er nicht, gibt es HTTP 500 statt einer Fehlermeldung, die das sagt.
- Docker trägt seine iptables-Regeln vor denen von ufw/firewalld ein. Bei
  veröffentlichten Ports greift keine Host-Firewall – `BIND_IP` ist die Grenze.
- `head` gehört bei der Passworterzeugung an den **Anfang** der Pipe. Am Ende
  beendet es `tr` per SIGPIPE, und unter `set -o pipefail` bricht das den Lauf ab.

## Repository

- Remote: `git@github.com:marcel-fratczak/t3ud-gsb11-docker.git` (SSH, public)
- Branch: `main`
- Commit-Identität vor dem ersten Commit prüfen:
  `git log -1 --format='%an <%ae>'`
