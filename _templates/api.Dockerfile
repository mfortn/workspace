# PHP-FPM 8.3 with common extensions for Laravel
FROM php:8.3-fpm

# System deps
RUN apt-get update && apt-get install -y \
    git curl zip unzip libzip-dev libpng-dev libonig-dev libxml2-dev libicu-dev libpq-dev libssl-dev \
    && docker-php-ext-install pdo pdo_mysql bcmath mbstring exif pcntl gd intl \
    && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working dir
WORKDIR /var/www/html

# Opcache recommended
RUN docker-php-ext-install opcache && \
    echo 'opcache.enable=1\nopcache.enable_cli=1\nopcache.validate_timestamps=1\nopcache.memory_consumption=128\nopcache.max_accelerated_files=10000\nopcache.save_comments=1' > /usr/local/etc/php/conf.d/opcache.ini
