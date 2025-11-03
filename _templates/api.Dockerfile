FROM php:8.2-fpm
ENV DEBIAN_FRONTEND=noninteractive

# 1) حزم البناء
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git curl zip unzip pkg-config \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
        libxml2-dev libzip-dev \
        libwebp-dev libxpm-dev \
        libonig-dev \
    ; rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# 2) ابني gd أولًا (لو فشل يبيّن السبب صريح)
RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd

# 3) ثبّت باقي الإضافات
RUN set -eux; \
    docker-php-ext-install -j"$(nproc)" \
        pdo_mysql zip mbstring exif pcntl bcmath opcache
