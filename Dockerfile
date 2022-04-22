FROM php:fpm-alpine

#RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk add --update --no-cache --virtual .build-dependencies $PHPIZE_DEPS shadow autoconf make && \
    apk add --update --no-cache imagemagick-dev g++ zlib-dev libmemcached-dev libpng-dev gmp-dev icu-dev libzip-dev && \
    usermod -u 1000 www-data && groupmod -g 1000 www-data && \
    pecl install apcu imagick memcached redis && \
    docker-php-ext-enable apcu imagick memcached redis && \
    docker-php-ext-install pdo mysqli pdo_mysql bcmath exif gd gmp intl opcache pcntl sockets zip && \
    pecl clear-cache && apk del .build-dependencies && rm -rf /tmp/*
