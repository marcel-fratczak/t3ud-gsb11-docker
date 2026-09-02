#!/usr/bin/env bash
#
# T3UD-GSB11 – Democontent installieren
#
# Legt die T3UD-2026-Beispielseite in einer bereits installierten GSB11-Instanz
# an: zwei Seiten (Programm, Impressionen), sechs Inhaltselemente, die Bilder
# und das Mandanten-Stylesheet mit der GSB11-Farbpalette.
#
# Das Skript ist wiederholbar: bereits vorhandener Democontent wird vorher
# entfernt. Es kann direkt aufgerufen werden, wenn beim Setup „nein" gewählt
# wurde, oder nach dem Austausch der Bilder erneut laufen.
#
# T3UD-GSB11 – install the demo content into an existing GSB11 instance:
# two pages, six content elements, the images and the tenant stylesheet.
# Repeatable – previously installed demo content is removed first.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=''; DIM=''; GREEN=''; RED=''; RESET=''
fi

section() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$RESET"; }
info()    { printf '   %s\n' "$*"; }
hint()    { printf '   %s%s%s\n' "$DIM" "$*" "$RESET"; }
ok()      { printf '   %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
die()     { printf '\n%sAbbruch:%s %s\n\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Vorbedingungen / preconditions
# ---------------------------------------------------------------------------
[ -f .env ] || die "Keine .env gefunden. Zuerst scripts/setup.sh ausführen."
set -a; . ./.env; set +a

C="docker compose"
in_php()  { $C exec -T php "$@"; }

# --default-character-set=utf8mb4 ist Pflicht, nicht Kosmetik: Der mysql-Client
# im Image verbindet sich sonst als latin1. Die Inhalte hier sind UTF-8, der
# Server würde sie als latin1 entgegennehmen und nach utf8mb4 umkodieren –
# aus 'ö' (C3 B6) wird dann 'Ã¶' (C3 83 C2 B6). Der Basis-Dump der Distribution
# entgeht dem nur, weil er selbst 'SET NAMES utf8mb4' mitbringt.
# Mandatory, not cosmetic: the mysql client in the image otherwise connects as
# latin1. The content here is UTF-8, so the server would take it as latin1 and
# transcode it to utf8mb4, turning 'ö' (C3 B6) into 'Ã¶' (C3 83 C2 B6). The
# distribution's base dump escapes this only because it carries its own
# 'SET NAMES utf8mb4'.
MYSQL="mysql --default-character-set=utf8mb4"

db_sql()  { $C exec -T -e MYSQL_PWD="$DB_PASSWORD" php \
    sh -c "$MYSQL -h db -u'$DB_USER' '$DB_NAME' $*"; }
db_val()  { $C exec -T -e MYSQL_PWD="$DB_PASSWORD" php \
    sh -c "$MYSQL -N -B -h db -u'$DB_USER' '$DB_NAME' -e \"$1\"" | tr -d '\r'; }

$C ps --status running --services 2>/dev/null | grep -qx php \
    || die "Der php-Container läuft nicht. Zuerst 'docker compose up -d' bzw. scripts/setup.sh ausführen."
in_php test -f composer.json \
    || die "In ./app liegt keine GSB11-Installation. Zuerst scripts/setup.sh ausführen."

section "Democontent"

# ---------------------------------------------------------------------------
# Hilfsfunktionen / helpers
# ---------------------------------------------------------------------------

# Backslash und einfaches Hochkomma für ein SQL-String-Literal maskieren.
# Reihenfolge zählt: erst der Backslash, sonst würde das eingefügte
# Escape-Zeichen der zweiten Regel gleich wieder mitmaskiert.
# Escape backslash and single quote for an SQL string literal. Order matters:
# backslash first, otherwise the escape character introduced by the second
# rule would be escaped again.
sql_escape() { sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }

NOW="$(date +%s)"

# ---------------------------------------------------------------------------
# Wurzelseite ermitteln / determine the site root page
# ---------------------------------------------------------------------------
ROOT_UID="$(db_val "SELECT uid FROM pages WHERE pid=0 AND is_siteroot=1 AND deleted=0 ORDER BY uid LIMIT 1;")"
[ -n "$ROOT_UID" ] || die "Keine Wurzelseite gefunden – ist die GSB11-Installation vollständig?"
info "Wurzelseite: uid $ROOT_UID"

# ---------------------------------------------------------------------------
# Vorhandenen Democontent entfernen / remove existing demo content
# ---------------------------------------------------------------------------
# Der Democontent ist an rowDescription bzw. am Slug erkennbar. Hart löschen
# statt deleted=1 setzen, damit ein erneuter Lauf keine Karteileichen im
# Papierkorb hinterlässt.
# Demo content is identified by rowDescription resp. by slug. Hard delete
# rather than deleted=1 so repeated runs leave no recycler leftovers.
db_sql "-e \"
    DELETE FROM tt_content WHERE rowDescription = 'T3UD-Democontent';
    DELETE FROM pages
     WHERE pid = $ROOT_UID
       AND slug IN ('/programm', '/impressionen')
       AND sys_language_uid = 0;
\""

# ---------------------------------------------------------------------------
# Seiten anlegen / create pages
# ---------------------------------------------------------------------------
# sorting zwischen 'GSB11' (256) und 'Seite nicht gefunden' (320), damit die
# Hauptnavigation die Reihenfolge GSB11 · Programm · Impressionen zeigt.
# sorting between 'GSB11' (256) and the 404 page (320) so the main navigation
# reads GSB11 · Programm · Impressionen.
create_page() { # create_page "Titel" "/slug" sorting
    db_sql "-e \"
        INSERT INTO pages (pid, title, slug, doktype, sorting, tstamp, crdate,
                           perms_user, perms_group, perms_everybody)
        VALUES ($ROOT_UID, '$1', '$2', 1, $3, $NOW, $NOW, 31, 31, 1);
    \""
    db_val "SELECT uid FROM pages WHERE pid=$ROOT_UID AND slug='$2' AND deleted=0 LIMIT 1;"
}

PAGE_PROGRAMM="$(create_page 'Programm' '/programm' 272)"
PAGE_IMPRESSIONEN="$(create_page 'Impressionen' '/impressionen' 288)"
ok "Seiten angelegt: Programm (uid $PAGE_PROGRAMM), Impressionen (uid $PAGE_IMPRESSIONEN)"

# ---------------------------------------------------------------------------
# Inhaltselemente anlegen / create content elements
# ---------------------------------------------------------------------------
# CType 'html' gibt das Markup unverändert aus – die Sektionen bringen ihr
# Layout über Klassen aus mandant.css mit. colPos 0 ist der „top-container",
# der über die volle Breite läuft; colPos 1 wäre die schmale Inhaltsspalte.
# CType 'html' outputs the markup verbatim – the sections bring their layout
# via classes from mandant.css. colPos 0 is the full-width "top-container";
# colPos 1 would be the narrow content column.
SQL_FILE="$(mktemp)"
trap 'rm -f "$SQL_FILE"' EXIT

add_element() { # add_element pid sorting datei
    local pid=$1 sorting=$2 file=$3
    [ -f "$file" ] || die "Democontent-Datei fehlt: $file"
    {
        printf "INSERT INTO tt_content (pid, CType, colPos, sorting, tstamp, crdate, rowDescription, bodytext) VALUES (%s, 'html', 0, %s, %s, %s, 'T3UD-Democontent', '" \
            "$pid" "$sorting" "$NOW" "$NOW"
        sql_escape < "$file"
        printf "');\n"
    } >> "$SQL_FILE"
}

add_element "$ROOT_UID"          128 demo/content/home-1-hero.html
add_element "$ROOT_UID"          256 demo/content/home-2-cards.html
add_element "$ROOT_UID"          384 demo/content/home-3-stats.html
add_element "$ROOT_UID"          512 demo/content/home-4-cta.html
add_element "$PAGE_PROGRAMM"     128 demo/content/programm.html
add_element "$PAGE_IMPRESSIONEN" 128 demo/content/impressionen.html

$C exec -T -e MYSQL_PWD="$DB_PASSWORD" php \
    sh -c "$MYSQL -h db -u'$DB_USER' '$DB_NAME'" < "$SQL_FILE"
ok "6 Inhaltselemente eingefügt"

# ---------------------------------------------------------------------------
# Bilder und Stylesheet / images and stylesheet
# ---------------------------------------------------------------------------
# Alle Schreibzugriffe laufen durch den Container, nicht über den Host.
# Grund: setup.sh chownt ./app am Ende auf www-data. Unter Linux schlägt ein
# Schreibzugriff des Host-Benutzers danach mit "Permission denied" fehl – auf
# macOS fällt das nicht auf, weil Docker Desktop die Eigentümer umschreibt.
# Every write goes through the container rather than the host: setup.sh chowns
# ./app to www-data, after which a host-side write fails with "permission
# denied" on Linux. macOS hides this because Docker Desktop remaps ownership.
IMG_TARGET=".build/public/fileadmin/user_upload/t3ud"
in_php mkdir -p "$IMG_TARGET"
$C cp demo/images/. "php:/var/www/html/$IMG_TARGET/" >/dev/null
ok "$(find demo/images -type f | wc -l | tr -d ' ') Bilder nach fileadmin/user_upload/t3ud/ kopiert"

# mandant.css ist der vom Kickstarter vorgesehene Anpassungspunkt und hängt als
# Symlink im Docroot (_assets/<hash>/StyleSheets/) – Überschreiben genügt.
# mandant.css is the kickstarter's designated customisation point and is
# symlinked into the docroot, so overwriting it is enough.
$C cp demo/css/mandant.css php:/var/www/html/Resources/Public/StyleSheets/mandant.css >/dev/null
ok "Mandanten-Stylesheet gesetzt"

# ---------------------------------------------------------------------------
# Markenfarben in den Site-Einstellungen / brand colours in the site settings
# ---------------------------------------------------------------------------
# --bs-primary/--bs-secondary erzeugt EXT:gsb_core als Inline-Style aus diesen
# Werten; sie gehören deshalb hierher und nicht ins Stylesheet.
# EXT:gsb_core emits --bs-primary/--bs-secondary as an inline style from these
# values, so they belong here rather than in the stylesheet.
#
# Die vorhandenen Farbzeilen werden zuerst entfernt, damit ein erneuter Lauf
# nicht anhängt, sondern ersetzt.
# Existing colour lines are dropped first so a repeated run replaces them
# instead of appending.
printf '%s\n' \
    "colors.colorGeneral.gsb-color-primary: '#007A89'" \
    "colors.colorGeneral.gsb-color-secondary: '#0B4D59'" \
    "colors.colorGeneral.gsb-color-quaternary: '#66DDEC'" \
    | in_php sh -c 'cat > /tmp/t3ud-colors.yaml'

in_php sh -c '
    set -e
    S=config/sites/gsb/settings.yaml
    [ -f "$S" ] || exit 0
    grep -v "^colors\.colorGeneral\." "$S" > /tmp/t3ud-settings.yaml || true
    cat /tmp/t3ud-colors.yaml >> /tmp/t3ud-settings.yaml
    cat /tmp/t3ud-settings.yaml > "$S"
    rm -f /tmp/t3ud-settings.yaml /tmp/t3ud-colors.yaml
'
ok "Markenfarben gesetzt (Petrol #007A89 / Achat #0B4D59)"

# ---------------------------------------------------------------------------
# Aufräumen / finalise
# ---------------------------------------------------------------------------
in_php chown -R www-data:www-data /var/www/html
in_php vendor/bin/typo3 cache:flush
ok "Caches geleert"

printf '\n'
info "Democontent installiert:"
info "  Startseite    : ${GSB_SCHEME:-http}://${FRONTEND_DOMAIN:-localhost:8080}/"
info "  Programm      : ${GSB_SCHEME:-http}://${FRONTEND_DOMAIN:-localhost:8080}/programm"
info "  Impressionen  : ${GSB_SCHEME:-http}://${FRONTEND_DOMAIN:-localhost:8080}/impressionen"
printf '\n'
hint "Eigene Bilder: Dateien in demo/images/ ersetzen und dieses Skript erneut aufrufen."
hint "Bei abweichender Dateiendung zusätzlich die src-Attribute in"
hint "demo/content/impressionen.html anpassen."
printf '\n'
