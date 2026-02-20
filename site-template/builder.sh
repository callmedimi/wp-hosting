#!/bin/sh
# ------------------------------------------------------------------------------
# WP-HOSTING BUILDER SCRIPT (THE EASIEST WAY)
# ------------------------------------------------------------------------------

# 1. Harvest per-page configs
if [ -f "/var/www/html/config-harvester.js" ]; then
    echo "🔍 Harvesting per-page Tailwind configs..."
    node /var/www/html/config-harvester.js || echo "❌ Harvester failed."
fi

# 2. Setup Master Output
# We compile to this hidden file first
MASTER_OUT="/var/www/html/wp-content/tailwind-all.css"
touch "$MASTER_OUT"
chmod 777 "$MASTER_OUT"

# � THE FIX: Link it to the ROOT so your <link href="/output.css"> works!
ln -sf "$MASTER_OUT" "/var/www/html/output.css"

# 3. Link to ALL themes (Bonus: Styles work in every theme automatically)
for theme in /var/www/html/wp-content/themes/*; do
    if [ -d "$theme" ]; then
        ln -sf "$MASTER_OUT" "$theme/output.css"
    fi
done

# 4. Search for Tailwind CLI
TAILWIND_CLI=""
if [ -f "/shared/node_modules/.bin/tailwindcss" ]; then
    TAILWIND_CLI="/shared/node_modules/.bin/tailwindcss"
elif [ -f "/shared/node_modules/tailwindcss/lib/cli.js" ]; then
    TAILWIND_CLI="/shared/node_modules/tailwindcss/lib/cli.js"
fi

# 5. Start Watching
if [ -f "/var/www/html/input.css" ]; then
    if [ -n "$TAILWIND_CLI" ]; then
        echo "🚀 Starting Tailwind watcher..."
        echo "   -> Access via: /output.css"
        
        case "$TAILWIND_CLI" in
            *.js) node "$TAILWIND_CLI" -i /var/www/html/input.css -o "$MASTER_OUT" --watch --poll ;;
            *) "$TAILWIND_CLI" -i /var/www/html/input.css -o "$MASTER_OUT" --watch --poll ;;
        esac
    else
        echo "❌ ERROR: tailwind cli not found."
        tail -f /dev/null
    fi
else
    echo "⚠️ Create /var/www/html/input.css to start."
    tail -f /dev/null
fi
