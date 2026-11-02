FROM php:8.1-fpm-alpine

RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    libxml2-dev \
    oniguruma-dev \
    freetype-dev \
    libjpeg-turbo-dev \
    libzip-dev \
    postgresql-dev \
    autoconf \
    g++ \
    make \
    icu-dev \
    zip \
    unzip

RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg

RUN docker-php-ext-install \
    intl \
    mysqli \
    pdo_mysql \
    pdo_pgsql \
    bcmath \
    mbstring \
    gd \
    zip \
    exif \
    xml \
    pcntl \
    opcache

RUN pecl install redis \
    && docker-php-ext-enable redis opcache

# install composer (best way)
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

CMD ["php-fpm"]
