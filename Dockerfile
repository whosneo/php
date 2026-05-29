FROM php:fpm-alpine

#RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# Install dependencies and adjust user
RUN set -eux && \
    apk add --no-cache --virtual .usermod shadow && \
    usermod -u 1000 www-data && \
    groupmod -g 1000 www-data && \
    apk del .usermod && \
    rm -rf /tmp/* /var/tmp/*

COPY --from=mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/

RUN install-php-extensions apcu bcmath bz2 exif gd gmp imagick intl memcached mysqli opcache pcntl pdo_mysql pdo_pgsql pgsql redis sockets sysvsem zip

RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini && \
    { \
        echo "apc.enable_cli = 1"; \
        echo "apc.shm_size = 128M"; \
        echo "opcache.enable = 1"; \
        echo "opcache.enable_cli = 1"; \
        echo "opcache.memory_consumption = 256"; \
        echo "opcache.interned_strings_buffer = 32"; \
        echo "opcache.max_accelerated_files = 20000"; \
        echo "opcache.validate_timestamps = 0"; \
        echo "memory_limit = 512M"; \
        echo "upload_max_filesize = 100M"; \
        echo "post_max_size = 100M"; \
        echo "date.timezone = Asia/Shanghai"; \
    } > /usr/local/etc/php/conf.d/99-custom.ini && \
    sed -i \
        -e 's/pm.max_children = 5/pm.max_children = 16/g' \
        -e 's/pm.start_servers = 2/pm.start_servers = 4/g' \
        -e 's/pm.min_spare_servers = 1/pm.min_spare_servers = 4/g' \
        -e 's/pm.max_spare_servers = 3/pm.max_spare_servers = 12/g' \
        /usr/local/etc/php-fpm.d/www.conf
