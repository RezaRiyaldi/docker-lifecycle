FROM php:5.6-fpm-alpine

# Install base dependencies
RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    libxml2-dev \
    freetype-dev \
    libjpeg-turbo-dev \
    libzip-dev \
    icu-dev \
    postgresql-dev \
    autoconf \
    g++ \
    make \
    zip \
    unzip

RUN docker-php-ext-configure gd \
    --with-freetype-dir=/usr/include/ \
    --with-jpeg-dir=/usr/include/

RUN docker-php-ext-install \
    intl \
    mysqli \
    pdo_mysql \
    bcmath \
    mbstring \
    gd \
    zip \
    exif \
    xml \
    pcntl \
    opcache

RUN pecl install redis-4.3.0 \
    && docker-php-ext-enable redis

# Install Composer versi 1.x (last version compatible with PHP 5.6)
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=1.10.26

# ===== CERTIFICATE =====
RUN apk add --no-cache ca-certificates openssl

# Copy certificate
COPY ssl/_wildcard.pxx.test.pem /usr/local/share/ca-certificates/

# RENAME ke .crt
RUN mv /usr/local/share/ca-certificates/_wildcard.pxx.test.pem /usr/local/share/ca-certificates/wildcard.pxx.test.crt

# Update CA certificates
RUN update-ca-certificates --fresh

# FORCE APPEND: tambahkan certificate ke CA bundle (PASTI BERHASIL)
RUN cat /usr/local/share/ca-certificates/wildcard.pxx.test.crt >> /etc/ssl/certs/ca-certificates.crt

# Set environment untuk curl
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
# ================================

RUN echo 'curl.cainfo = "/etc/ssl/certs/ca-certificates.crt"' >> /usr/local/lib/php.ini \
    && echo 'openssl.cafile = "/etc/ssl/certs/ca-certificates.crt"' >> /usr/local/lib/php.ini

WORKDIR /var/www

CMD ["php-fpm"]