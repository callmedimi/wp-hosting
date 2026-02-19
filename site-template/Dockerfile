# ==========================================
# WP-HOSTING CUSTOM WORDPRESS
# ==========================================
FROM wordpress:latest

# We removed the external php-extension-installer because it was 
# being blocked by Docker Hub (403 Forbidden).
# IonCube and other tools are now handled in wp-init.sh at runtime.

# Copy our custom initialization script
COPY wp-init.sh /usr/local/bin/wp-init.sh
RUN chmod +x /usr/local/bin/wp-init.sh

# Set the entrypoint to our script
ENTRYPOINT ["/usr/local/bin/wp-init.sh"]
