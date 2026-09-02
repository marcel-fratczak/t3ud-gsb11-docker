# SBOM

Hier legt der Workflow [`security.yml`](../.github/workflows/security.yml) die
CycloneDX-Stücklisten der drei Container-Images ab:

| Datei | Image |
|-------|-------|
| `php.cdx.json` | eigenes PHP-FPM-Image (`docker/php`) |
| `nginx.cdx.json` | eigenes nginx-Image (`docker/nginx`) |
| `db.cdx.json` | `mariadb` in der Version aus `compose.yaml` |

Die Dateien entstehen bei jedem Lauf neu, werden über
[`scripts/normalize-sbom.py`](../scripts/normalize-sbom.py) normalisiert und
nur dann zurückcommittet, wenn sich tatsächlich etwas geändert hat.

**Warum normalisiert?** Trivy schreibt in jede SBOM eine frische Seriennummer,
einen Zeitstempel, den Image-Digest und die gefundenen Schwachstellen. Ohne
Normalisierung würde damit jeder wöchentliche Lauf einen Commit erzeugen, auch
wenn sich kein einziges Paket geändert hat. Das Skript entfernt diese Felder,
streicht den Architektur-Qualifier aus den purls (damit amd64 und arm64
dieselbe Datei ergeben) und sortiert die Komponenten deterministisch. Übrig
bleibt ein reines Komponenten-Inventar – ein Diff hier bedeutet immer eine
echte Änderung an der Software-Zusammensetzung.

Wer die aktuelle SBOM ohne CI erzeugen will:

```bash
docker build --pull -t t3ud-gsb11-php docker/php
```

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/out" aquasec/trivy image --format cyclonedx --output /out/sbom/php.cdx.json t3ud-gsb11-php
```

```bash
python3 scripts/normalize-sbom.py sbom/php.cdx.json t3ud-gsb11-php
```
