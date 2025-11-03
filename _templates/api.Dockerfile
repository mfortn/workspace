FROM php:8.2-fpm

RUN apt-get update && apt-get install -y \    git curl zip unzip libpng-dev libjpeg-dev libfreetype6-dev libonig-dev libxml2-dev libzip-dev \    && docker-php-ext-configure gd --with-freetype --with-jpeg \    && docker-php-ext-install pdo pdo_mysql gd zip mbstring exif pcntl bcmath opcache \    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

USER www-data
