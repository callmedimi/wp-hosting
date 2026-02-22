# Check if we are running as root
IS_ROOT=false
if [ "$(id -u)" = '0' ]; then
    IS_ROOT=true
fi

if [ ! -f "$MARKER" ]; then
    echo "[WP-HOSTING] First boot — installing components..."

    # --- 1. Install IonCube Loader ---
    echo "[WP-HOSTING] Installing IonCube Loader..."
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    # Handle PHP 8.4+ layout if needed, but for now 8.3 is standard
    EXT_DIR=$(php -r "echo ini_get('extension_dir');")
    
    # Check if user provided the loaders in the site root (useful for offline install)
    LOCAL_PKG="/var/www/html/ioncube_loaders_lin_x86-64.tar.gz"
    if [ -f "$LOCAL_PKG" ]; then
        echo "[WP-HOSTING] Found local ionCube package at $LOCAL_PKG"
        cp "$LOCAL_PKG" /tmp/ioncube.tar.gz
    else
        echo "[WP-HOSTING] Downloading ionCube from official source..."
        curl -sL --connect-timeout 15 --max-time 120 --retry 3 \
            -o /tmp/ioncube.tar.gz \
            "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
    fi
    
    if [ -f /tmp/ioncube.tar.gz ] && [ -s /tmp/ioncube.tar.gz ]; then
        tar -xzf /tmp/ioncube.tar.gz -C /tmp/
        ION_SO="${EXT_DIR}/ioncube_loader_lin_${PHP_VER}.so"
        
        if [ "$IS_ROOT" = true ]; then
            cp "/tmp/ioncube/ioncube_loader_lin_${PHP_VER}.so" "$ION_SO"
            chmod 755 "$ION_SO"
            echo "zend_extension=$ION_SO" > /usr/local/etc/php/conf.d/00-ioncube.ini
            echo "[WP-HOSTING] IonCube installed to $ION_SO"
        else
            echo "[WP-HOSTING] ERROR: Cannot install IonCube (not running as root)."
        fi
        rm -rf /tmp/ioncube /tmp/ioncube.tar.gz
    else
        echo "[WP-HOSTING] IonCube package missing or download failed."
        rm -f /tmp/ioncube.tar.gz
    fi

    # --- 2. Install WP-CLI ---
    echo "[WP-HOSTING] Installing WP-CLI..."
    
    LOCAL_WP_CLI="/var/www/html/wp-cli.phar"
    if [ -f "$LOCAL_WP_CLI" ]; then
        echo "[WP-HOSTING] Found local WP-CLI at $LOCAL_WP_CLI"
        if [ "$IS_ROOT" = true ]; then
            cp "$LOCAL_WP_CLI" /usr/local/bin/wp
        else
            cp "$LOCAL_WP_CLI" /tmp/wp && chmod +x /tmp/wp
        fi
    else
        echo "[WP-HOSTING] Downloading WP-CLI from official source..."
        if [ "$IS_ROOT" = true ]; then
            curl -sL --connect-timeout 15 --max-time 60 --retry 3 \
                -o /usr/local/bin/wp \
                "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
        else
            curl -sL --connect-timeout 15 --max-time 60 --retry 3 \
                -o /tmp/wp \
                "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
        fi
    fi
    
    if [ "$IS_ROOT" = true ] && [ -f /usr/local/bin/wp ]; then
        chmod +x /usr/local/bin/wp
        echo "[WP-HOSTING] WP-CLI installed!"
    elif [ -f /tmp/wp ]; then
        chmod +x /tmp/wp
        echo "[WP-HOSTING] WP-CLI installed to /tmp/wp (No root permissions for /usr/local/bin)"
    else
        echo "[WP-HOSTING] WP-CLI download failed (will retry next restart)"
    fi

    # Mark as initialized (only if both succeeded or at least WP-CLI)
    if [ -f /usr/local/bin/wp ] || [ -f /tmp/wp ]; then
        [ "$IS_ROOT" = true ] && touch "$MARKER"
    fi
fi

# Ensure /usr/local/bin/wp is available for the next steps
if [ ! -f /usr/local/bin/wp ] && [ -f /tmp/wp ]; then
    alias wp='/tmp/wp'
fi

# --- 3. Adjust User (www-data) to match host SYS_UID/SYS_GID ---
if [ "$IS_ROOT" = true ] && [ -n "$SYS_UID" ] && [ -n "$SYS_GID" ]; then
    echo "[WP-HOSTING] Syncing www-data UID/GID with host ($SYS_UID:$SYS_GID)..."
    groupmod -g "$SYS_GID" www-data 2>/dev/null || true
    usermod -u "$SYS_UID" -g "$SYS_GID" www-data 2>/dev/null || true
    # Final ownership check for web root
    chown -R www-data:www-data /var/www/html
fi

# --- 4. Install Persian language (needs WordPress + DB to be ready) ---
if [ ! -f /var/www/html/.lang-installed ] && command -v wp >/dev/null; then
    (
        # Wait for DB to be potentially ready (polite wait)
        sleep 5
        
        # Loop until DB is actually ready (max 120 attempts = 2 mins)
        echo "[WP-HOSTING] Waiting for Database connection..."
        for i in {1..120}; do
            if wp db check --allow-root > /dev/null 2>&1; then
                echo "[WP-HOSTING] Database Connected! Checking if site is installed..."
                if wp core is-installed --allow-root > /dev/null 2>&1; then
                    echo "[WP-HOSTING] WordPress is installed. Fixing Permalinks and Language..."
                    wp rewrite structure '/%postname%/' --allow-root
                    wp rewrite flush --allow-root
                    wp language core install fa_IR --activate --allow-root 2>/dev/null
                    if [ $? -eq 0 ]; then
                        touch /var/www/html/.lang-installed
                        echo "[WP-HOSTING] Persian language installed successfully!"
                    fi
                else
                    echo "[WP-HOSTING] WordPress not installed yet. Skipping language setup for now."
                fi
                break
            fi
            [ $((i % 10)) -eq 0 ] && echo "[WP-HOSTING] DB not ready yet... (Attempt $i/120)"
            sleep 2
        done
    ) &
fi

# Hand off to the original WordPress entrypoint
exec docker-entrypoint.sh apache2-foreground
