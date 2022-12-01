FROM php:fpm-alpine

#RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk add --update --no-cache --virtual .build-dependencies shadow && \
    usermod -u 1000 www-data && groupmod -g 1000 www-data && \
    apk del .build-dependencies && \
    apk add --update --no-cache diffutils git && \
    rm -rf /tmp/* && \
    curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions apcu imagick memcached redis pdo mysqli pdo_mysql bcmath exif gd gmp intl opcache pcntl sockets zip && \
    sed -i 's/pm.max_children = 5/pm.max_children = 16/g' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.start_servers = 2/pm.start_servers = 4/g' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.min_spare_servers = 1/pm.min_spare_servers = 4/g' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/pm.max_spare_servers = 3/pm.max_spare_servers = 12/g' /usr/local/etc/php-fpm.d/www.conf && \
    cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini && \
    sed -i 's/memory_limit = 128M/memory_limit = 512M/g' /usr/local/etc/php/php.ini && \
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 32M/g' /usr/local/etc/php/php.ini && \
    sed -i 's/post_max_size = 8M/post_max_size = 32M/g' /usr/local/etc/php/php.ini && \
    echo "apc.enable_cli = 1" >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini && \
    echo "opcache.enable_cli = 1" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini && \
    echo "opcache.interned_strings_buffer = 32" >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini
