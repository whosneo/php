FROM php:fpm-alpine

#RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories

# Install dependencies and adjust user
RUN apk add --update --no-cache diffutils git shadow && \
    usermod -u 1000 www-data && groupmod -g 1000 www-data && \
    apk del shadow && \
    rm -rf /var/cache/apk/* /tmp/*

# Install PHP extensions installer
RUN curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions

# Install PHP extensions
RUN install-php-extensions apcu imagick memcached redis pgsql pdo_pgsql mysqli pdo_mysql bcmath exif gd gmp intl opcache pcntl sockets zip sysvsem bz2

# Configure PHP-FPM and PHP
RUN sed -i -e 's/pm.max_children = 5/pm.max_children = 16/g' \
           -e 's/pm.start_servers = 2/pm.start_servers = 4/g' \
           -e 's/pm.min_spare_servers = 1/pm.min_spare_servers = 4/g' \
           -e 's/pm.max_spare_servers = 3/pm.max_spare_servers = 12/g' \
           /usr/local/etc/php-fpm.d/www.conf && \
    cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini && \
    sed -i -e 's/memory_limit = 128M/memory_limit = 512M/g' \
           -e 's/upload_max_filesize = 2M/upload_max_filesize = 100M/g' \
           -e 's/post_max_size = 8M/post_max_size = 100M/g' \
           /usr/local/etc/php/php.ini && \
    echo "apc.enable_cli = 1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini && \
    echo "opcache.enable_cli = 1" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini && \
    echo "opcache.interned_strings_buffer = 32" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini
