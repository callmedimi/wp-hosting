#!/bin/bash
# ==========================================
# WP-HOSTING ENTRYPOINT (OPENLITESPEED)
# ==========================================
# Installs IonCube, WP-CLI, and configures OLS specific settings on first boot.

MARKER="/usr/local/lsws/.wp-hosting-initialized"
DOCROOT="/var/www/vhosts/localhost/html"
export PATH=$PATH:/usr/local/bin:/usr/local/lsws/lsphp82/bin

IS_ROOT=false
if [ "$(id -u)" = '0' ]; then
    IS_ROOT=true
fi

if [ ! -f "$MARKER" ]; then
    echo "[WP-HOSTING] First boot — installing components for OpenLiteSpeed..."

    # --- 1. Install IonCube Loader ---
    echo "[WP-HOSTING] Installing IonCube Loader..."
    PHP_VER="8.2"
    EXT_DIR=$(php -r "echo ini_get('extension_dir');")
    
    LOCAL_PKG="${DOCROOT}/ioncube_loaders_lin_x86-64.tar.gz"
    if [ -f "$LOCAL_PKG" ]; then
        cp "$LOCAL_PKG" /tmp/ioncube.tar.gz
    else
        curl -sL --connect-timeout 15 -o /tmp/ioncube.tar.gz "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
    fi
    
    if [ -f /tmp/ioncube.tar.gz ]; then
        tar -xzf /tmp/ioncube.tar.gz -C /tmp/
        ION_SO="${EXT_DIR}/ioncube_loader_lin_${PHP_VER}.so"
        if [ "$IS_ROOT" = true ]; then
            cp "/tmp/ioncube/ioncube_loader_lin_${PHP_VER}.so" "$ION_SO"
            chmod 755 "$ION_SO"
            echo "zend_extension=$ION_SO" > /usr/local/lsws/lsphp82/etc/php/8.2/mods-available/00-ioncube.ini
            echo "[WP-HOSTING] IonCube installed to $ION_SO"
        fi
        rm -rf /tmp/ioncube /tmp/ioncube.tar.gz
    fi

    # --- 2. Install WP-CLI ---
    echo "[WP-HOSTING] Installing WP-CLI..."
    LOCAL_WP_CLI="${DOCROOT}/wp-cli.phar"
    if [ -f "$LOCAL_WP_CLI" ]; then
        [ "$IS_ROOT" = true ] && cp "$LOCAL_WP_CLI" /usr/local/bin/wp
    else
        curl -sL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x /usr/local/bin/wp
    fi

    [ "$IS_ROOT" = true ] && touch "$MARKER"
fi

# --- 2.5 PHP INI Adjustments ---
PHP_INI="/usr/local/lsws/lsphp82/etc/php/8.2/litespeed/php.ini"
if [ -f "$PHP_INI" ]; then
    echo "[WP-HOSTING] Applying PHP resource limits..."
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = 128M/" "$PHP_INI"
    sed -i "s/post_max_size = .*/post_max_size = 128M/" "$PHP_INI"
    sed -i "s/max_execution_time = .*/max_execution_time = 300/" "$PHP_INI"
    if grep -q 'max_input_vars' "$PHP_INI"; then
        sed -i 's/^;\?max_input_vars = .*/max_input_vars = 3000/' "$PHP_INI"
    else
        echo 'max_input_vars = 3000' >> "$PHP_INI"
    fi
fi

cd "$DOCROOT"

# --- 3. Setup core WP files & wp-config if missing ---
if [ ! -f wp-includes/version.php ]; then
    echo "[WP-HOSTING] Downloading WordPress Core..."
    wp core download --allow-root --path="$DOCROOT"
fi

# We use a hardcoded, clean wp-config.php that doesn't rely on OLS passing environment arrays.
# Because OLS runs PHP in detached detached processes, env vars get lost.
if [ ! -f wp-config.php ]; then
    echo "[WP-HOSTING] Creating standalone wp-config.php..."
    cat << 'EOF' > wp-config.php
<?php
define( 'WP_CACHE', true );
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
    $_SERVER['HTTPS'] = 'on';
}

EOF
    echo "define( 'DB_NAME', '${WORDPRESS_DB_NAME:-wordpress}' );" >> wp-config.php
    echo "define( 'DB_USER', '${WORDPRESS_DB_USER:-wordpress}' );" >> wp-config.php
    echo "define( 'DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}' );" >> wp-config.php
    echo "define( 'DB_HOST', '${WORDPRESS_DB_HOST:-db}' );" >> wp-config.php
    cat << 'EOF' >> wp-config.php
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

define('AUTH_KEY',         'b42500d44a7331fbdb6f0d0792f83ae8eb3f1213');
define('SECURE_AUTH_KEY',  '71dd8fa42e605860a030ee3439c50467ce943694');
define('LOGGED_IN_KEY',    '3190697de5305b55c6cce8dd09580ef21454c5de');
define('NONCE_KEY',        '410935a17403fa8ba780a3d2e9fb33581794218c');
define('AUTH_SALT',        'a3aad5dffe7205c2051d61577c0dfd458b221249');
define('SECURE_AUTH_SALT', '9dee5f6f7a232060ddf86205b7b2b72169bda6b3');
define('LOGGED_IN_SALT',   'bb48aba69b9d2cba95636759d722a4d70ad389d8');
define('NONCE_SALT',       '20f535b3da30ea271a5ad0d7e7e31945a0e50279');

$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

if (file_exists(__DIR__ . '/wp-custom.php')) {
    include_once __DIR__ . '/wp-custom.php';
}

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

    echo "[WP-HOSTING] Creating default LiteSpeed .htaccess..."
    cat << 'EOF' > .htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF

    echo "[WP-HOSTING] Creating wp-custom.php with resource limits & Redis config..."
    cat << 'EOF' > wp-custom.php
<?php
/* Managed by WP-HOSTING */
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '1024M');
define('FS_METHOD', 'direct');

/* Redis Configuration (Object Cache) */
define('WP_REDIS_HOST', 'redis');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);

/* Security */
define('DISALLOW_FILE_EDIT', true);
EOF
fi

# --- 4. Adjust permissions & language ---
echo "[WP-HOSTING] Initializing LiteSpeed Cache directories..."
mkdir -p "${DOCROOT}/wp-content/litespeed/cssjs"
mkdir -p "${DOCROOT}/wp-content/litespeed/css"
mkdir -p "${DOCROOT}/wp-content/litespeed/js"
mkdir -p /tmp/lscache

echo "[WP-HOSTING] Adjusting permissions for nobody:nogroup (OLS)..."
chown -R nobody:nogroup "$DOCROOT"
chown -R nobody:nogroup /tmp/lscache
chmod -R 755 "$DOCROOT"
chmod -R 777 /tmp/lscache

if [ ! -f "${DOCROOT}/.lang-installed" ]; then
    (
        sleep 10
        if wp db check --allow-root --path="$DOCROOT" > /dev/null 2>&1; then
            if wp core is-installed --allow-root --path="$DOCROOT" > /dev/null 2>&1; then
                wp language core install fa_IR --activate --allow-root --path="$DOCROOT" 2>/dev/null
                if [ $? -eq 0 ]; then
                    touch "${DOCROOT}/.lang-installed"
                    chown nobody:nogroup "${DOCROOT}/.lang-installed"
                    echo "[WP-HOSTING] Persian language configured."
                fi
            fi
        fi
        
        echo "[WP-HOSTING] Applying automated PageSpeed Optimizations..."
        if wp plugin is-installed litespeed-cache --path="$DOCROOT" --allow-root > /dev/null 2>&1; then
            echo "[WP-HOSTING] Activating LiteSpeed Cache..."
            wp plugin activate litespeed-cache --path="$DOCROOT" --allow-root 2>/dev/null
            
            # Safe CSS/JS Optimizations
            wp option update litespeed.conf.optm-css_min true --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-css_comb false --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-css_async true --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-js_min true --path="$DOCROOT" --allow-root 2>/dev/null
            
            # Crucial for avoiding 521 and JS undefined errors
            wp option update litespeed.conf.optm-js_defer 1 --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-js_comb false --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-js_exc "jquery.min.js\njquery.js" --path="$DOCROOT" --allow-root 2>/dev/null
            
            # Guest Mode Delivery
            wp option update litespeed.conf.optm-guestmode true --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-guestmode_optm true --path="$DOCROOT" --allow-root 2>/dev/null
            wp option update litespeed.conf.optm-ucss true --path="$DOCROOT" --allow-root 2>/dev/null
            
            wp litespeed-purge all --path="$DOCROOT" --allow-root 2>/dev/null
            echo "[WP-HOSTING] Optimizations applied."
        fi
    ) &
fi

# --- 4.5 Auto-tune OpenLiteSpeed ---
echo "[WP-HOSTING] Tuning OpenLiteSpeed for maximum performance..."
CONFIG="/usr/local/lsws/conf/httpd_config.conf"
if [ -f "$CONFIG" ]; then
    # Increase PHP workers (Respecting Memory)
    sed -i 's/PHP_LSAPI_CHILDREN=.*/PHP_LSAPI_CHILDREN=200/g' "$CONFIG"
    sed -i '/extProcessor lsphp/,/^}/{s/maxConns.*/maxConns                200/}' "$CONFIG"
    # Trust Proxy Headers (Cloudflare/Traefik)
    if ! grep -q "useIpInProxyHeader" "$CONFIG"; then
        sed -i '/tuning  {/a \  useIpInProxyHeader      1' "$CONFIG"
    fi
    # Fix Listener Port (8088 -> 80)
    sed -i 's/address                  \*:8088/address                  \*:80/g' "$CONFIG"
    # Fix Virtual Host Root to match our Docker mount
    sed -i 's|vhRoot                   Example/|vhRoot                   /var/www/vhosts/localhost/|g' "$CONFIG"
    
    # Remove redundant/conflicting listeners and templates at the bottom
    sed -i '/listener HTTP {/,/}/d' "$CONFIG"
    sed -i '/listener HTTPS {/,/}/d' "$CONFIG"
    sed -i '/vhTemplate docker {/,/}/d' "$CONFIG"

    # Enable Gzip & Brotli
    sed -i "s/enableGzip.*/enableGzip              1/" "$CONFIG"
    if ! grep -q "compressibleTypes" "$CONFIG"; then
        sed -i "/enableGzip/a \  compressibleTypes       text/*, application/javascript, application/json, application/xml, application/rss+xml, image/svg+xml, application/font-woff, application/font-woff2, font/woff2, font/ttf" "$CONFIG"
    fi
fi

# Apply High-Performance Virtual Host Config
VHCONF="/usr/local/lsws/conf/vhosts/Example/vhconf.conf"
if [ -f "$VHCONF" ]; then
    echo "[WP-HOSTING] Overwriting vhconf.conf with optimized settings..."
    cat << 'VHEOF' > "$VHCONF"
docRoot $VH_ROOT/html/
enableGzip 1
enableBr 1
enableDynGzip 1
gzipCompressionLevel 6
brStaticEnable 1
brDynamicEnable 1

index {
  useServer 0
  indexFiles index.php, index.html
  autoIndex 0
}

context / {
  allowBrowse 1
  location $DOC_ROOT/
  rewrite {
    RewriteFile .htaccess
  }
  addDefaultCharset off
}

rewrite {
  enable 1
  logLevel 0
  rules <<<END_rules
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
END_rules
}

module cache {
  ls_enabled 1
  checkPrivateCache 1
  checkPublicCache 1
  maxCacheObjSize 10000000
  maxStaleAge 200
  qsCache 1
  reqCookieCache 1
  respCookieCache 1
  ignoreReqCacheCtrl 1
  ignoreRespCacheCtrl 0
  storagePath /tmp/lscache/
}

expires {
  enableExpires 1
  expiresByType application/javascript=A2592000,text/css=A2592000,image/png=A2592000,image/gif=A2592000,image/jpeg=A2592000,image/webp=A2592000,image/avif=A2592000,image/svg+xml=A2592000,application/font-woff=A2592000,application/font-woff2=A2592000,font/woff=A2592000,font/woff2=A2592000,font/ttf=A2592000
}

accessControl {
  deny
  allow *
}

general {
  enableContextAC 0
}
VHEOF
fi

# --- 5. Start OpenLiteSpeed ---
echo "[WP-HOSTING] Starting OpenLiteSpeed Web Server..."
/usr/local/lsws/bin/lswsctrl start
tail -f /usr/local/lsws/logs/access.log /usr/local/lsws/logs/error.log
