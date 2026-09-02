# Democontent

Die T3UD-Beispielseite, die [`scripts/demo-content.sh`](../scripts/demo-content.sh)
in eine bestehende GSB11-Installation einspielt.

## Was hier liegt

```
demo/
├── content/          Inhaltselemente als HTML-Fragmente
│   ├── home-1-hero.html        Startseite: Hero mit Terminal-Fenster
│   ├── home-2-cards.html       Startseite: drei Karten
│   ├── home-3-stats.html       Startseite: Zahlen-Band
│   ├── home-4-cta.html         Startseite: Abschluss-Aufruf
│   ├── programm.html           Seite „Programm": Timeline
│   └── impressionen.html       Seite „Impressionen": Galerie
├── css/mandant.css   Mandanten-Stylesheet (GSB11-Farbpalette)
└── images/           Sieben Grafiken für die Galerie
```

## Wie es eingespielt wird

Jede Datei aus `content/` wird zu einem Inhaltselement vom Typ **`html`**. Der
GSB11 gibt dessen Inhalt unverändert aus – das Layout bringen die Sektionen
über CSS-Klassen aus `mandant.css` selbst mit. Deshalb genügen sechs Elemente
für drei gestaltete Seiten, und deshalb braucht die Galerie keine
FAL-Referenzen: Die Bilder liegen schlicht unter
`fileadmin/user_upload/t3ud/` und werden per `<img src>` eingebunden.

Alle Elemente landen in **colPos 0**, dem `top-container` des GSB11 – der Spalte,
die über die volle Seitenbreite läuft. `colPos 1` wäre die schmale Inhaltsspalte.

Erkennbar ist der Democontent an `tt_content.rowDescription = 'T3UD-Democontent'`
und an den Slugs `/programm` und `/impressionen`. Genau daran räumt das Skript
zu Beginn auf, bevor es neu einfügt – ein zweiter Lauf erzeugt also keine
Dubletten.

## Eigene Inhalte

**Texte ändern:** Datei in `content/` bearbeiten, dann:

```bash
./scripts/demo-content.sh
```

**Bilder austauschen:** Eigene Dateien nach `images/` legen, gleicher Dateiname,
und das Skript erneut aufrufen. Bei abweichender Dateiendung – etwa `.jpg`
statt `.svg` – zusätzlich die `src`-Attribute in `content/impressionen.html`
anpassen.

Empfohlene Seitenverhältnisse: `veranstaltungsort` läuft als breites Banner
(2,4:1, im Original 1536 × 640), die sechs Galeriebilder als 4:3 (1024 × 768).
Andere Formate funktionieren auch – die Galerie beschneidet per
`object-fit: cover`.

**Farben ändern:** Primär- und Sekundärfarbe stehen **nicht** in `mandant.css`,
sondern werden von `EXT:gsb_core` als Inline-Style aus den Site-Einstellungen
erzeugt. Das Skript schreibt sie nach
`app/config/sites/gsb/settings.yaml`:

```yaml
colors.colorGeneral.gsb-color-primary: '#007A89'
colors.colorGeneral.gsb-color-secondary: '#0B4D59'
colors.colorGeneral.gsb-color-quaternary: '#66DDEC'
```

Alles Abgeleitete – Verläufe, Karten, Timeline, Buttons – steht in
`css/mandant.css`. Bootstrap kompiliert die Komponentenfarben fest ein, deshalb
müssen die `--bs-btn-*`-Variablen dort zusätzlich überschrieben werden.

**Democontent wieder entfernen:**

```bash
docker compose exec -T php sh -c 'mysql -h db -u gsb11 -p"$DB_PASSWORD" gsb11 -e "
  DELETE FROM tt_content WHERE rowDescription = \"T3UD-Democontent\";
  DELETE FROM pages WHERE slug IN (\"/programm\", \"/impressionen\");"'
docker compose exec php vendor/bin/typo3 cache:flush
```

## Hinweis zu den Inhalten

Das Programm auf der Seite „Programm" ist **frei erfunden** und kein offizielles
Programm der TYPO3 University Days; die Abbildungen sind **stilisierte
Grafiken** und zeigen keine realen Personen, Orte oder Veranstaltungen. Beides
ist auf den Seiten selbst als Hinweisbox gekennzeichnet. Wer den Democontent
als Grundlage für eine echte Seite nimmt, sollte beide Hinweisboxen entfernen –
und die Inhalte natürlich ersetzen.
