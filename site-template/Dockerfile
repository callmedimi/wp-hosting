FROM wordpress:latest

# Build arguments for mirrors
ARG MIRROR="mirror.arvancloud.ir"
ARG WP_MIRROR="https://fa.wordpress.org/latest-fa_IR.tar.gz"

# Fix apt sources for Debian Trixie (Bookworm/Testing)
RUN sed -i "s/deb.debian.org/$MIRROR/g" /etc/apt/sources.list.d/debian.sources && \
    apt-get update

# 1. Install Persian WordPress & Core (Download instead of COPY)
RUN curl -sL --connect-timeout 20 --max-time 300 --retry 5 -o /tmp/wp-fa.tar.gz "$WP_MIRROR" && \
    tar -xzf /tmp/wp-fa.tar.gz -C /usr/src/ && \
    rm /tmp/wp-fa.tar.gz && \
    chown -R www-data:www-data /usr/src/wordpress/

# 2. Use official extension installer
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# 3. Install Extensions
RUN install-php-extensions \
    mysqli \
    pdo_mysql \
    zip \
    soap \
    intl \
    exif \
    opcache \
    bcmath \
    gmp \
    redis \
    imagick \
    memcached

ARG IONCUBE_MIRROR="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
ARG WPCLI_MIRROR="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"

# 4. Install IonCube Loader (Download instead of COPY)
RUN curl -sL --connect-timeout 20 --max-time 300 --retry 5 -o /tmp/ioncube.tar.gz "$IONCUBE_MIRROR" && \
    tar -xzf /tmp/ioncube.tar.gz -C /tmp/ && \
    cp /tmp/ioncube/ioncube_loader_lin_$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')*.so $(php -r "echo ini_get('extension_dir');")/ioncube_loader_lin_$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;').so && \
    echo "zend_extension=ioncube_loader_lin_$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;').so" > /usr/local/etc/php/conf.d/00-ioncube.ini && \
    rm -rf /tmp/ioncube /tmp/ioncube.tar.gz

# 5. Install WP-CLI (Download instead of COPY)
RUN curl -sL --connect-timeout 20 --max-time 300 --retry 5 -o /usr/local/bin/wp "$WPCLI_MIRROR" && \
    chmod +x /usr/local/bin/wp

# PHP.ini Optimizations
RUN { \
    echo 'upload_max_filesize = 128M'; \
    echo 'post_max_size = 128M'; \
    echo 'memory_limit = 512M'; \
    echo 'max_execution_time = 300'; \
    } > /usr/local/etc/php/conf.d/wp-recommended.ini

RUN a2enmod rewrite headers expires
