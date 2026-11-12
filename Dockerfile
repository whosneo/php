# syntax=docker/dockerfile:1
FROM php:fpm

# 调整 www-data 的 UID/GID（与常见宿主机用户匹配）
RUN <<'EOF'
set -eux
usermod -u 1000 www-data
groupmod -g 1000 www-data
# usermod 只改家目录里的属主，基础镜像里 uid/gid 33 的文件要单独改
find / -xdev -uid 33 -exec chown -h www-data {} +
find / -xdev -gid 33 -exec chgrp -h www-data {} +
if find / -xdev \( -uid 33 -o -gid 33 \) | grep -q .; then
    echo "leftover uid/gid 33" >&2
    find / -xdev \( -uid 33 -o -gid 33 \) -ls >&2
    exit 1
fi
test "$(id -u www-data)" = 1000
test "$(id -g www-data)" = 1000
EOF

# 编译扩展后只保留运行时库。直接 purge --auto-remove -dev 包会把 .so 依赖的运行库一起卸掉。
RUN <<'EOF'
set -eux
export DEBIAN_FRONTEND=noninteractive
savedAptMark="$(apt-mark showmanual)"
apt-get update
apt-get install -y --no-install-recommends \
    $PHPIZE_DEPS \
    libbz2-dev \
    libfreetype-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libicu-dev \
    libzip-dev \
    libpq-dev \
    libgmp-dev \
    libmagickwand-dev \
    libmemcached-dev \
    zlib1g-dev \
    ghostscript \
    fonts-urw-base35
docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp
docker-php-ext-install -j"$(nproc)" \
    bcmath \
    bz2 \
    exif \
    gd \
    gmp \
    intl \
    mysqli \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    sockets \
    sysvsem \
    zip

pecl_install() {
    package="$1"
    options="$2"
    attempt=1
    until pecl install --configureoptions "$options" "$package"; do
        if [ "$attempt" -ge 5 ]; then
            echo "pecl install ${package} failed after ${attempt} attempts" >&2
            exit 1
        fi
        echo "pecl install ${package} failed (attempt ${attempt}), retrying in $((attempt * 10))s..." >&2
        rm -rf /tmp/pear /tmp/pear-build-*
        sleep $((attempt * 10))
        attempt=$((attempt + 1))
    done
}

export MAKEFLAGS="-j$(nproc)"
# pecl.php.net 会抖动；选项写死，避免构建在交互提问处挂起
pecl_install apcu 'enable-apcu-debug="no"'
pecl_install imagick 'with-imagick="autodetect"'
pecl_install memcached 'with-libmemcached-dir="no" with-zlib-dir="no" with-system-fastlz="no" with-zstd="no" enable-memcached-igbinary="no" enable-memcached-msgpack="no" enable-memcached-json="yes" enable-memcached-protocol="no" enable-memcached-sasl="yes" enable-memcached-session="yes"'
pecl_install redis 'enable-redis-igbinary="no" enable-redis-lzf="no" enable-redis-zstd="no" enable-redis-msgpack="no" enable-redis-phpser="no" enable-redis-lz4="no" with-liblz4="no"'
docker-php-ext-enable apcu imagick memcached redis

# 扩展 .so 不属于任何 apt 包，用 ldd 把它们的运行库标成手动安装后再清理
apt-mark auto '.*' >/dev/null
apt-mark manual $savedAptMark
apt-mark manual ghostscript fonts-urw-base35
{
    find /usr/local/lib/php/extensions -type f -name '*.so' -exec ldd '{}' ';'
    ldd /usr/local/bin/php /usr/local/sbin/php-fpm
} | awk '/=>/ { so = $(NF-1); if (so !~ /^\//) next; if (index(so, "/usr/local/") == 1) next; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' | sort -u > /tmp/so-patterns
test -s /tmp/so-patterns
dpkg-query --search $(cat /tmp/so-patterns) > /tmp/so-owners 2>/tmp/so-missing || true
runtimeLibs="$(awk 'sub(":$", "", $1) { print $1 }' /tmp/so-owners | sort -u)"
if [ -z "$runtimeLibs" ]; then
    echo "failed to map shared libraries to packages" >&2
    cat /tmp/so-patterns /tmp/so-missing >&2
    exit 1
fi
apt-mark manual $runtimeLibs
# 官方基础镜像留着 phpize 的编译器，方便派生镜像继续编扩展。这里扩展已经编完。
apt-mark auto autoconf dpkg-dev file g++ gcc libc6-dev make pkg-config re2c
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
apt-get dist-clean
docker-php-source delete
rm -rf /tmp/pear /tmp/pear-build-* /tmp/so-patterns /tmp/so-owners /tmp/so-missing /tmp/* /var/tmp/* /root/.pearrc

php --version
php -m
for ext in apcu bcmath bz2 curl exif gd gmp imagick intl mbstring memcached mysqli openssl pcntl pdo_mysql pdo_pgsql pgsql redis sockets sodium sysvsem xml zip; do
    php -m | grep -qi "^${ext}$" || { echo "missing extension: ${ext}" >&2; php -m >&2; exit 1; }
done
php -r 'exit(function_exists("opcache_get_status") ? 0 : 1);'
php -r '$i = gd_info(); exit(($i["FreeType Support"] && $i["JPEG Support"] && $i["WebP Support"]) ? 0 : 1);'
php -r '$g = imagecreatetruecolor(8, 8); imagepng($g, "/tmp/gd.png"); imagejpeg($g, "/tmp/gd.jpg"); imagewebp($g, "/tmp/gd.webp");'
php -r '$im = new Imagick(); $im->newImage(8, 8, "red"); $im->setImageFormat("webp"); if (strlen($im->getImageBlob()) < 8) exit(1); $im->setImageFormat("pdf"); $im->writeImage("/tmp/im.pdf"); $pdf = new Imagick(); $pdf->setResolution(36, 36); $pdf->readImage("/tmp/im.pdf"); exit($pdf->getImageWidth() < 1 ? 1 : 0);'
find /usr/local/lib/php/extensions -type f -name '*.so' -exec ldd '{}' ';' | awk '/not found/ { print; missing = 1 } END { exit missing ? 1 : 0 }'
command -v gs >/dev/null
rm -f /tmp/gd.png /tmp/gd.jpg /tmp/gd.webp /tmp/im.pdf
EOF

# 使用生产配置并写入自定义 php.ini
RUN <<'EOF'
set -eux
cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
cat > /usr/local/etc/php/conf.d/99-custom.ini <<'INI'
apc.enable_cli = 1
apc.shm_size = 64M
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 32
opcache.max_accelerated_files = 65536
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
realpath_cache_size = 40960
realpath_cache_ttl = 600
memory_limit = 256M
upload_max_filesize = 100M
post_max_size = 100M
max_input_vars = 5000
date.timezone = Asia/Shanghai
INI
sed -i \
    -e 's/pm.max_children = 5/pm.max_children = 10/g' \
    -e 's/pm.start_servers = 2/pm.start_servers = 3/g' \
    -e 's/pm.min_spare_servers = 1/pm.min_spare_servers = 3/g' \
    -e 's/pm.max_spare_servers = 3/pm.max_spare_servers = 6/g' \
    -e 's/;pm.max_requests = 500/pm.max_requests = 500/g' \
    -e 's/;request_terminate_timeout = 0/request_terminate_timeout = 300s/g' \
    -e 's/;request_slowlog_timeout = 0/request_slowlog_timeout = 5s/g' \
    -e 's|;slowlog = log/$pool.log.slow|slowlog = /proc/self/fd/2|g' \
    -e 's|;pm.status_path = /status|pm.status_path = /status|g' \
    /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.max_children = 10$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.start_servers = 3$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.min_spare_servers = 3$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.max_spare_servers = 6$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.max_requests = 500$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^request_terminate_timeout = 300s$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^request_slowlog_timeout = 5s$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^slowlog = /proc/self/fd/2$' /usr/local/etc/php-fpm.d/www.conf
grep -q '^pm.status_path = /status$' /usr/local/etc/php-fpm.d/www.conf
php-fpm -t
php -r 'exit((ini_get("date.timezone") === "Asia/Shanghai" && ini_get("memory_limit") === "256M" && ini_get("max_input_vars") === "5000" && ini_get("opcache.enable_cli") === "1") ? 0 : 1);'
php -r 'exit(opcache_get_status(false) ? 0 : 1);'
EOF
