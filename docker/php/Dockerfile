# GSB11 – PHP-FPM-Laufzeit / PHP-FPM runtime
#
# Basis: offizielle GSB11-Distribution (itzbund/gsb-sitepackage, TYPO3 13.4 LTS,
# PHP 8.3). Die installierten Pakete und PHP-Erweiterungen entsprechen dem
# offiziellen DDEV-Webimage des GSB11-Sitepackage-Kickstarters: ImageMagick und
# Ghostscript für die Bild-/PDF-Verarbeitung, exiftool und qpdf für Metadaten,
# die PHP-Erweiterung redis ist für EXT:gsb_core Pflicht.
#
# Base: official GSB11 distribution (itzbund/gsb-sitepackage, TYPO3 13.4 LTS,
# PHP 8.3). Packages and PHP extensions mirror the kickstarter's official DDEV
# web image; the redis PHP extension is mandatory for EXT:gsb_core.

FROM php:8.5-fpm-bookworm

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        default-mysql-client \
        ghostscript \
        git \
        imagemagick \
        libfcgi-bin \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libimage-exiftool-perl \
        qpdf \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" gd intl mbstring mysqli zip opcache \
    && pecl install apcu redis \
    && docker-php-ext-enable apcu redis \
    && rm -rf /var/lib/apt/lists/* /usr/src/* /tmp/pear

COPY php.ini /usr/local/etc/php/conf.d/zz-gsb11.ini
COPY fpm-healthcheck.conf /usr/local/etc/php-fpm.d/zz-gsb11.conf
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1

WORKDIR /var/www/html
