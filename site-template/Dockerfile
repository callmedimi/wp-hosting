# ==========================================
# WP-HOSTING CUSTOM WORDPRESS (OLS VERSION)
# ==========================================
FROM litespeedtech/openlitespeed:1.7.19-lsphp82

# Install available PHP extensions for OLS and utilities
RUN apt-get update && apt-get install -y \
    lsphp82-curl \
    lsphp82-imagick \
    lsphp82-intl \
    lsphp82-mysql \
    lsphp82-opcache \
    lsphp82-redis \
    curl \
    wget \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Fix PHP path for WP-CLI
RUN ln -sf /usr/local/lsws/lsphp82/bin/php /usr/local/bin/php

# Copy our custom initialization script
COPY wp-init.sh /usr/local/bin/wp-init.sh
RUN chmod +x /usr/local/bin/wp-init.sh

# Set the entrypoint to our script
ENTRYPOINT ["/usr/local/bin/wp-init.sh"]
