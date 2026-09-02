#!/usr/bin/env bash
#
# T3UD-GSB11 – lokale Installation
#
# Fragt drei Dinge ab (Democontent, Port, Administrator-Passwort), schreibt
# .env und installiert den Government Site Builder 11 nach den offiziellen
# Schritten des Sitepackage-Kickstarters
# (https://gitlab.opencode.de/bmi/government-site-builder-11) nach ./app.
#
# T3UD-GSB11 – local installation. Asks three questions (demo content, port,
# administrator password), writes .env and installs Government Site Builder 11
# into ./app following the official kickstarter steps.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# ---------------------------------------------------------------------------
# Ausgabe-Helfer / output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=''; DIM=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi

section() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$RESET"; }
info()    { printf '   %s\n' "$*"; }
hint()    { printf '   %s%s%s\n' "$DIM" "$*" "$RESET"; }
ok()      { printf '   %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()    { printf '   %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()     { printf '\n%sAbbruch:%s %s\n\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Verwendung: scripts/setup.sh [Optionen]

Ohne Optionen stellt das Skript drei Fragen und installiert anschließend den
kompletten Stack. Mit den Optionen läuft es vollständig ohne Rückfragen –
gedacht für die Generalprobe vor dem Vortrag und für CI.

  --demo                Democontent (T3UD-2026-Seite) mitinstallieren
  --no-demo             Democontent überspringen
  --port <1-65535>      Host-Port für das Frontend (Standard: 8080)
  --admin-password <pw> Passwort für den TYPO3-Administrator
  -y, --yes             Keine Rückfragen; nicht gesetzte Werte per Standard
                        (Port 8080, Democontent ja, Zufallspasswort)
  -h, --help            Diese Hilfe

Usage: scripts/setup.sh [options] – see the German text above. Without options
the script asks three questions; with them it runs fully non-interactively.
USAGE
}

# ---------------------------------------------------------------------------
# Eingabe-Helfer / input helpers
# ---------------------------------------------------------------------------

# Zeichen, die in .env gefahrlos stehen können. Einfache Hochkommas,
# Backslash, $ und Backticks sind ausgeschlossen: .env wird sowohl von der
# Shell als auch vom Compose-Parser gelesen, und die beiden behandeln
# Escapes unterschiedlich.
# Characters safe for .env – .env is read by both the shell and the compose
# parser, which escape differently, so quotes/backslash/$/backtick are out.
SAFE_RE='^[A-Za-z0-9!#%*+,./:=?@^_~-]+$'

ask() { # ask VARNAME "Frage" ["default"]
    local __var=$1 __q=$2 __def=${3-} __in=''
    while :; do
        if [ -n "$__def" ]; then
            read -r -p "   $__q [$__def]: " __in || die "Eingabe abgebrochen."
            __in=${__in:-$__def}
        else
            read -r -p "   $__q: " __in || die "Eingabe abgebrochen."
        fi
        [ -n "$__in" ] && break
        warn "Pflichtfeld – bitte ausfüllen."
    done
    printf -v "$__var" '%s' "$__in"
}

ask_yn() { # ask_yn VARNAME "Frage" j|n   -> setzt "true"/"false"
    local __var=$1 __q=$2 __def=${3:-j} __prompt __in=''
    [ "$__def" = j ] && __prompt='J/n' || __prompt='j/N'
    while :; do
        read -r -p "   $__q [$__prompt]: " __in || die "Eingabe abgebrochen."
        __in=${__in:-$__def}
        case "$__in" in
            [jJyY]*) printf -v "$__var" '%s' 'true';  return ;;
            [nN]*)   printf -v "$__var" '%s' 'false'; return ;;
            *)       warn "Bitte j oder n." ;;
        esac
    done
}

# head steht bewusst vorne: am Ende der Pipe würde es tr nach 28 Bytes per
# SIGPIPE beenden – unter 'set -o pipefail' bricht das die Installation ab.
# head deliberately comes first: at the end of the pipe it would kill tr with
# SIGPIPE after 28 bytes, which aborts the run under 'set -o pipefail'.
gen_pw() {
    local raw
    raw=$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
    printf '%s' "${raw:0:28}"
}

typo3_pw_ok() { # mind. 8 Zeichen, Groß, Klein, Ziffer, Sonderzeichen
    local p=$1
    [ ${#p} -ge 8 ]            || return 1
    [[ $p == *[a-z]*        ]] || return 1
    [[ $p == *[A-Z]*        ]] || return 1
    [[ $p == *[0-9]*        ]] || return 1
    [[ $p == *[^a-zA-Z0-9]* ]] || return 1
    return 0
}

ask_secret() { # ask_secret VARNAME "Frage"
    local __var=$1 __q=$2 __in='' __in2=''
    while :; do
        read -r -s -p "   $__q (leer = zufällig erzeugen): " __in || die "Eingabe abgebrochen."
        echo
        if [ -z "$__in" ]; then
            __in="$(gen_pw).Aa1"
            ok "zufälliges Passwort erzeugt"
            break
        fi
        if ! [[ $__in =~ $SAFE_RE ]]; then
            warn "Erlaubt sind Buchstaben, Ziffern und ! # % * + , - . / : = ? @ ^ _ ~"
            continue
        fi
        if ! typo3_pw_ok "$__in"; then
            warn "TYPO3-Richtlinie: mind. 8 Zeichen mit Groß-, Kleinbuchstabe, Ziffer und Sonderzeichen."
            continue
        fi
        read -r -s -p "   Wiederholen: " __in2 || die "Eingabe abgebrochen."
        echo
        [ "$__in" = "$__in2" ] && break
        warn "Die Eingaben stimmen nicht überein."
    done
    printf -v "$__var" '%s' "$__in"
}

port_ok() { [[ $1 =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# ---------------------------------------------------------------------------
# Optionen / options
# ---------------------------------------------------------------------------
OPT_DEMO=''; OPT_PORT=''; OPT_ADMIN_PW=''; NONINTERACTIVE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --demo)            OPT_DEMO=true ;;
        --no-demo)         OPT_DEMO=false ;;
        --port)            OPT_PORT="${2-}"; shift ;;
        --admin-password)  OPT_ADMIN_PW="${2-}"; shift ;;
        -y|--yes)          NONINTERACTIVE=true ;;
        -h|--help)         usage; exit 0 ;;
        *)                 usage >&2; die "Unbekannte Option: $1" ;;
    esac
    shift
done

[ -n "$OPT_PORT" ] && ! port_ok "$OPT_PORT" && die "--port braucht eine Zahl zwischen 1 und 65535."
if [ -n "$OPT_ADMIN_PW" ]; then
    [[ $OPT_ADMIN_PW =~ $SAFE_RE ]] || die "--admin-password enthält Zeichen, die in .env nicht sicher sind."
    typo3_pw_ok "$OPT_ADMIN_PW" || die "--admin-password erfüllt die TYPO3-Richtlinie nicht (mind. 8 Zeichen, Groß, Klein, Ziffer, Sonderzeichen)."
fi

# Alle drei Werte per Option gesetzt = keine Frage mehr offen
# All three values provided via options = nothing left to ask
if [ -n "$OPT_DEMO" ] && [ -n "$OPT_PORT" ] && [ -n "$OPT_ADMIN_PW" ]; then
    NONINTERACTIVE=true
fi

# ===========================================================================
# 0 – Vorbedingungen / preflight
# ===========================================================================
printf '\n%s T3UD-GSB11 – Installation %s\n' "$BOLD" "$RESET"
hint "Government Site Builder 11 (TYPO3 13.4 LTS) als lokaler Docker-Stack."

section "Vorbedingungen"
command -v docker >/dev/null 2>&1 || die "Docker ist nicht installiert."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 fehlt ('docker compose version' schlägt fehl)."
docker info >/dev/null 2>&1 || die "Kein Zugriff auf den Docker-Daemon. Läuft Docker Desktop bzw. der Dienst?"
ok "Docker und Compose v2 verfügbar"

# ===========================================================================
# 1 – Konfiguration / configuration
# ===========================================================================
REUSE_ENV=false
if [ -f .env ]; then
    section "Vorhandene Konfiguration"
    if [ "$NONINTERACTIVE" = true ] || [ ! -t 0 ]; then
        REUSE_ENV=true
        info "Vorhandene .env wird übernommen."
    else
        info "Es existiert bereits eine .env."
        ask_yn REUSE_ENV "Vorhandene .env unverändert übernehmen?" j
    fi
fi

if [ "$REUSE_ENV" != true ]; then
    if [ "$NONINTERACTIVE" != true ] && [ ! -t 0 ]; then
        die "Ohne interaktives Terminal bitte -y bzw. die Optionen verwenden (scripts/setup.sh --help)."
    fi

    section "Einrichtung"

    # ---- 1/3 Democontent --------------------------------------------------
    if [ -n "$OPT_DEMO" ]; then
        WITH_DEMO="$OPT_DEMO"
    elif [ "$NONINTERACTIVE" = true ]; then
        WITH_DEMO=true
    else
        hint "Der Democontent legt die T3UD-2026-Beispielseite an: Startseite mit Hero,"
        hint "Programm-Timeline und Bildergalerie im GSB11-Farbschema."
        ask_yn WITH_DEMO "1/3  Democontent mitinstallieren?" j
    fi

    # ---- 2/3 Port ---------------------------------------------------------
    if [ -n "$OPT_PORT" ]; then
        HTTP_PORT="$OPT_PORT"
    elif [ "$NONINTERACTIVE" = true ]; then
        HTTP_PORT=8080
    else
        hint "Unter diesem Port läuft die Seite auf http://localhost."
        while :; do
            ask HTTP_PORT "2/3  Host-Port für das Frontend" "8080"
            port_ok "$HTTP_PORT" && break
            warn "Bitte einen Port zwischen 1 und 65535 angeben."
        done
    fi

    # ---- 3/3 Administrator-Passwort ---------------------------------------
    if [ -n "$OPT_ADMIN_PW" ]; then
        TYPO3_ADMIN_PASSWORD="$OPT_ADMIN_PW"
    elif [ "$NONINTERACTIVE" = true ]; then
        TYPO3_ADMIN_PASSWORD="$(gen_pw).Aa1"
    else
        hint "Zugang zum TYPO3-Backend unter /typo3, Benutzername 'admin'."
        ask_secret TYPO3_ADMIN_PASSWORD "3/3  Passwort für den Administrator"
    fi

    # ---- Feste Werte für den lokalen Betrieb ------------------------------
    # Alles Weitere ist für eine Notebook-Installation eindeutig und wird
    # deshalb nicht abgefragt. Wer davon abweichen will, ändert .env.
    # Everything else is unambiguous for a laptop install and therefore not
    # asked. Adjust .env to deviate.
    GSB_SCHEME=http
    BIND_IP=127.0.0.1
    FRONTEND_DOMAIN="localhost:$HTTP_PORT"
    BACKEND_DOMAIN="$FRONTEND_DOMAIN"
    # Nur localhost/127.0.0.1 mit genau diesem Port gelten als vertrauenswürdig.
    # Wer die Seite im Netz veröffentlicht, erweitert das Muster – siehe
    # docs/reverse-proxy.md.
    # Only localhost/127.0.0.1 on exactly this port count as trusted. Extend the
    # pattern when publishing the site – see docs/reverse-proxy.md.
    TRUSTED_HOSTS_PATTERN="(localhost|127\.0\.0\.1):$HTTP_PORT"
    TYPO3_ADMIN_USER=admin
    TYPO3_ADMIN_EMAIL="admin@localhost"
    DB_NAME=gsb11
    DB_USER=gsb11
    DB_PASSWORD="$(gen_pw)"
    DB_ROOT_PASSWORD="$(gen_pw)"

    # ---- Zusammenfassung --------------------------------------------------
    section "Zusammenfassung"
    info "Adresse       : $GSB_SCHEME://$FRONTEND_DOMAIN/"
    info "Backend       : $GSB_SCHEME://$FRONTEND_DOMAIN/typo3 (Benutzer: $TYPO3_ADMIN_USER)"
    if [ "$WITH_DEMO" = true ]; then
        info "Democontent   : wird installiert"
    else
        info "Democontent   : wird übersprungen (später: scripts/demo-content.sh)"
    fi
    info "Datenbank     : $DB_NAME, Passwörter werden zufällig erzeugt"

    if [ "$NONINTERACTIVE" != true ]; then
        echo
        ask_yn CONFIRM "Installation mit diesen Einstellungen starten?" j
        [ "$CONFIRM" = true ] || die "Auf Wunsch abgebrochen. Es wurde nichts verändert."
    fi

    # ---- .env schreiben ---------------------------------------------------
    umask 077
    cat > .env <<ENVEOF
# T3UD-GSB11 – erzeugt von scripts/setup.sh am $(date -Iseconds)
# Diese Datei enthält Passwörter und gehört nicht in die Versionsverwaltung.
# Generated by scripts/setup.sh. Contains secrets – never commit.

# --- Erreichbarkeit / reachability ---
GSB_SCHEME=$GSB_SCHEME
FRONTEND_DOMAIN=$FRONTEND_DOMAIN
BACKEND_DOMAIN=$BACKEND_DOMAIN
TRUSTED_HOSTS_PATTERN='$TRUSTED_HOSTS_PATTERN'
BIND_IP=$BIND_IP
HTTP_PORT=$HTTP_PORT

# --- Reverse Proxy (leer = lokaler Betrieb) / reverse proxy (empty = local) ---
# Siehe docs/reverse-proxy.md / see docs/reverse-proxy.md
REVERSE_PROXY_IP=
REVERSE_PROXY_SSL=

# --- TYPO3 ---
TYPO3_CONTEXT=Production
ALLOWED_MEDIA_DOMAINS='*'
WITH_DEMO=$WITH_DEMO

# --- Datenbank / database ---
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD='$DB_PASSWORD'
DB_ROOT_PASSWORD='$DB_ROOT_PASSWORD'

# --- Backend-Administrator (nur beim Erst-Setup verwendet) ---
TYPO3_ADMIN_USER=$TYPO3_ADMIN_USER
TYPO3_ADMIN_PASSWORD='$TYPO3_ADMIN_PASSWORD'
TYPO3_ADMIN_EMAIL=$TYPO3_ADMIN_EMAIL

# --- E-Mail / mail (für die lokale Demo nicht nötig / not needed locally) ---
MAIL_TRANSPORT=sendmail
MAIL_SMTP_SERVER=
MAIL_SMTP_ENCRYPT=
MAIL_SMTP_USER=
MAIL_SMTP_PASSWORD=
MAIL_FROM_ADDRESS=
MAIL_FROM_NAME=
ENVEOF
    umask 022
    chmod 600 .env
    ok ".env geschrieben (chmod 600)"
fi

set -a; . ./.env; set +a
: "${WITH_DEMO:=true}"
# Option schlägt den Wert aus .env / the option overrides the value from .env
[ -n "$OPT_DEMO" ] && WITH_DEMO="$OPT_DEMO"

# ===========================================================================
# 2 – Installation / installation
# ===========================================================================
C="docker compose"
in_php() { $C exec -T php "$@"; }

# --default-character-set=utf8mb4: Der mysql-Client im Image verbindet sich
# sonst als latin1 und kodiert UTF-8-Inhalte doppelt. Der Grundinhalts-Dump
# der Distribution bringt zwar sein eigenes 'SET NAMES utf8mb4' mit, aber
# darauf sollte sich nicht verlassen, wer hier später eine Anweisung ergänzt.
# The mysql client in the image otherwise connects as latin1 and double-encodes
# UTF-8 content. The distribution's dump carries its own 'SET NAMES utf8mb4',
# but nobody adding a statement here later should have to rely on that.
db_sql() { $C exec -T -e MYSQL_PWD="$DB_PASSWORD" php \
    sh -c "mysql --default-character-set=utf8mb4 -h db -u'$DB_USER' '$DB_NAME' $*"; }

section "Installation"

info "[1/9] Container bauen und starten ..."
mkdir -p app
$C up -d --build --wait db
$C up -d --build php web

info "[2/9] GSB11 per Composer installieren (dauert einige Minuten) ..."
if in_php test -f composer.json; then
    hint "app/ enthält bereits ein Projekt – übersprungen."
else
    in_php composer create-project --no-interaction --remove-vcs itzbund/gsb-sitepackage .
fi

info "[3/9] Basis-URL der Site anpassen ..."
in_php sh -c "sed -i -E \
    -e 's#https?://%env\(FRONTEND_DOMAIN\)%#%env(GSB_SCHEME)%://%env(FRONTEND_DOMAIN)%#g' \
    -e 's#https?://%env\(BACKEND_DOMAIN\)%#%env(GSB_SCHEME)%://%env(BACKEND_DOMAIN)%#g' \
    config/sites/gsb/config.yaml" || true

info "[4/9] TYPO3 einrichten ..."
in_php vendor/bin/typo3 setup --force --no-interaction \
    --driver=mysqli --host=db --port=3306 \
    --dbname="$DB_NAME" --username="$DB_USER" --password="$DB_PASSWORD" \
    --project-name="T3UD-GSB11" \
    --admin-username="${TYPO3_ADMIN_USER:-admin}" \
    --admin-user-password="$TYPO3_ADMIN_PASSWORD" \
    --admin-email="${TYPO3_ADMIN_EMAIL:-}" \
    --server-type=apache

info "[5/9] GSB11-Grundinhalte importieren ..."
db_sql "< .ddev/initial-setup/mysql-db.sql"
in_php vendor/bin/typo3 database:updateschema

info "[6/9] Extensions einrichten ..."
in_php vendor/bin/typo3 extension:setup

info "[7/9] Platzhalterbild kopieren ..."
in_php sh -c 'mkdir -p .build/public/fileadmin/user_upload \
    && chmod -R 2775 .build/public/fileadmin \
    && cp Resources/Public/Images/placeholder_image.jpg \
          .build/public/fileadmin/user_upload/placeholder_image.jpg' || true

info "[8/9] Statisches TypoScript aktivieren ..."
db_sql "-e \"UPDATE sys_template SET include_static_file='EXT:gsb_sitepackage/Configuration/TypoScript/' WHERE pid=1 AND deleted=0;\"" || true

info "[9/9] Caches leeren und Dateirechte setzen ..."
in_php vendor/bin/typo3 cache:flush
# Setup lief als root; php-fpm bedient Requests als www-data und muss var/,
# config/system und fileadmin schreiben können (sonst HTTP 500 auf Linux).
# Setup ran as root; php-fpm serves requests as www-data and must be able to
# write var/, config/system and fileadmin (otherwise HTTP 500 on Linux).
in_php chown -R www-data:www-data /var/www/html

ok "GSB11 installiert"

# ===========================================================================
# 3 – Democontent / demo content
# ===========================================================================
if [ "$WITH_DEMO" = true ]; then
    ./scripts/demo-content.sh
fi

# ===========================================================================
# 4 – Abschluss / summary
# ===========================================================================
printf '\n%s══ Fertig ══%s\n\n' "$BOLD" "$RESET"
info "Frontend : $GSB_SCHEME://$FRONTEND_DOMAIN/"
info "Backend  : $GSB_SCHEME://$FRONTEND_DOMAIN/typo3"
info "Login    : ${TYPO3_ADMIN_USER:-admin}"
hint "Das Passwort steht in .env (TYPO3_ADMIN_PASSWORD)."

if [ "$WITH_DEMO" != true ]; then
    printf '\n'
    hint "Democontent später nachinstallieren: ./scripts/demo-content.sh"
fi

printf '\n'
hint "Stack stoppen: docker compose down   ·   alles zurücksetzen: docker compose down -v && rm -rf app"
hint "Seite im Netz veröffentlichen: docs/reverse-proxy.md"
printf '\n'
