# 🛠️ Shared Tools & Database Access Guide

This guide is for **Site Administrators**, **Theme Developers**, and **Content Managers**. It explains how to access your database and use the pre-installed development tools.

---

## 📋 Table of Contents

1. [Database Access (phpMyAdmin)](#database-access-phpmyadmin)
2. [File Management](#file-management)
3. [Development Tools](#development-tools)
4. [Email Testing](#email-testing)
5. [Container Access](#container-access)
6. [Troubleshooting](#troubleshooting)

---

## 🗄️ Database Access (phpMyAdmin)

### Accessing phpMyAdmin

**URL**: `https://pma.yourdomain.com`

We use a single, centralized phpMyAdmin instance for all WordPress sites on the server.

### Login Credentials

When you open phpMyAdmin, you'll see a login screen with three fields:

| Field | What to Enter | Example |
|-------|---------------|---------|
| **Server** | Your database container name | `client1_db` |
| **Username** | Your database username | `client1_user` |
| **Password** | Your database password | `your_secret_password` |

### Finding Your Credentials

**Method 1: Via File Manager**

1. Go to `https://files.yourdomain.com`
2. Navigate to `sites/[your-site]/.env`
3. Look for these lines:
   ```
   DB_HOST=client1_db
   DB_USER=client1_user
   DB_PASSWORD=your_password
   DB_NAME=client1_db
   ```

**Method 2: Via CLI**

```bash
# SSH into server
ssh user@your-server

# View credentials
cat /opt/wp-hosting/sites/client1/.env | grep DB_
```

**Method 3: Ask Your Admin**

Contact your server administrator for the credentials.

### Important Notes

⚠️ **Never use `localhost` or `127.0.0.1`** for the Server field. You **must** use the container name (e.g., `client1_db`).

✅ **Container naming pattern**: If your site folder is `myshop`, the database container is `myshop_db`.

### Common phpMyAdmin Tasks

#### Viewing Tables

1. After login, click your database name in the left sidebar
2. You'll see all WordPress tables (wp_posts, wp_users, etc.)
3. Click any table to view its contents

#### Running SQL Queries

1. Click the **SQL** tab at the top
2. Enter your query:
   ```sql
   SELECT * FROM wp_posts WHERE post_status = 'publish' LIMIT 10;
   ```
3. Click **Go**

#### Exporting Database

1. Click the **Export** tab
2. Choose **Quick** export method
3. Click **Go**
4. Save the `.sql` file

#### Importing Database

1. Click the **Import** tab
2. Click **Choose File**
3. Select your `.sql` file
4. Click **Go**

⚠️ **Warning**: Importing will overwrite existing data. Always backup first!

#### Search and Replace

Useful for changing domain names:

1. Click the **Search** tab
2. Enter old value: `http://oldsite.com`
3. Enter new value: `https://newsite.com`
4. Click **Go**

Or use WP-CLI (recommended):
```bash
docker exec client1_wp wp search-replace 'http://oldsite.com' 'https://newsite.com'
```

---

## 📁 File Management

### FileBrowser Access

**URL**: `https://files.yourdomain.com`

FileBrowser provides a web-based file manager for all your sites.

### Features

- **Upload/Download**: Drag and drop files
- **Edit**: Built-in code editor for PHP, CSS, JS
- **Create**: New files and folders
- **Delete**: Remove files and folders
- **Move**: Drag files between folders
- **Search**: Find files by name
- **Share**: Generate download links

### Accessing Your Site Files

1. Navigate to `https://files.yourdomain.com`
2. Login with your credentials
3. Go to `sites/[your-site]/`

### Directory Structure

```
sites/client1/
├── backups/              # Database dumps
├── html/                 # WordPress root
│   ├── wp-content/
│   │   ├── themes/       # Your themes
│   │   ├── plugins/      # Your plugins
│   │   └── uploads/      # Media files
│   ├── wp-config.php
│   └── ...
└── .env                  # Site configuration
```

### Editing Files

1. Click on any file (e.g., `style.css`)
2. Click the **Edit** button (pencil icon)
3. Make your changes
4. Click **Save**

### Uploading Files

**Method 1: Drag and Drop**
1. Open the destination folder
2. Drag files from your computer
3. Drop them in the browser window

**Method 2: Upload Button**
1. Click the **Upload** button
2. Select files
3. Click **Open**

### Downloading Files

1. Select file(s) by clicking the checkbox
2. Click the **Download** button
3. File will download to your computer

---

## 🎨 Development Tools

### TailwindCSS (Automatic Compilation)

You **do not** need to install Node.js or run `npm run watch`. The server handles this automatically.

#### How It Works

1. Edit any file in your theme:
   - `style.css`
   - `input.css`
   - Any `.php` file with Tailwind classes

2. The builder container automatically:
   - Detects changes
   - Compiles Tailwind CSS
   - Generates `output.css`

3. Refresh your browser to see changes

#### Using Tailwind Classes

Add classes directly to your HTML/PHP:

```php
<div class="container mx-auto px-4">
    <h1 class="text-3xl font-bold text-blue-600">
        Welcome to My Site
    </h1>
    <p class="mt-4 text-gray-700">
        This is styled with Tailwind CSS
    </p>
</div>
```

#### Customizing Tailwind

Edit `tailwind.config.js` in your theme folder:

```javascript
module.exports = {
  theme: {
    extend: {
      colors: {
        'brand-blue': '#1e40af',
        'brand-red': '#dc2626',
      },
      fontFamily: {
        'vazir': ['Vazirmatn', 'sans-serif'],
      },
    },
  },
}
```

#### Troubleshooting Tailwind

**CSS not updating?**

1. Hard refresh: `Ctrl + F5` (Windows) or `Cmd + Shift + R` (Mac)
2. Check if `tailwind.config.js` exists
3. Restart builder container:
   ```bash
   docker restart client1_builder
   ```

**Classes not working?**

1. Ensure you're using valid Tailwind classes
2. Check if `output.css` is being loaded:
   ```php
   <link rel="stylesheet" href="<?php echo get_template_directory_uri(); ?>/output.css">
   ```

### Icon Library (Lucide)

The **Lucide** icon library is pre-installed and ready to use.

#### Getting the Sprite File

**One-time setup** (ask your admin or use FileBrowser):

```bash
# Via CLI
docker exec client1_builder cp /app/node_modules/lucide/dist/lucide-sprite.svg /app/
```

This copies `lucide-sprite.svg` to your theme folder.

#### Using Icons

Once the sprite file is in your theme:

```php
<!-- Camera Icon -->
<svg class="w-6 h-6 text-gray-700">
    <use href="<?php echo get_template_directory_uri(); ?>/lucide-sprite.svg#camera" />
</svg>

<!-- Heart Icon -->
<svg class="w-8 h-8 text-red-500">
    <use href="<?php echo get_template_directory_uri(); ?>/lucide-sprite.svg#heart" />
</svg>

<!-- Menu Icon -->
<svg class="w-6 h-6 text-white">
    <use href="<?php echo get_template_directory_uri(); ?>/lucide-sprite.svg#menu" />
</svg>
```

#### Available Icons

Browse all icons at: [lucide.dev/icons](https://lucide.dev/icons)

Replace `#camera` with any icon name from the library.

#### Styling Icons

Icons are SVGs, so you can style them with Tailwind:

```php
<!-- Different sizes -->
<svg class="w-4 h-4">...</svg>  <!-- Small -->
<svg class="w-6 h-6">...</svg>  <!-- Medium -->
<svg class="w-8 h-8">...</svg>  <!-- Large -->

<!-- Different colors -->
<svg class="text-blue-500">...</svg>
<svg class="text-red-600">...</svg>
<svg class="text-gray-400">...</svg>

<!-- Hover effects -->
<svg class="hover:text-blue-700 transition-colors">...</svg>
```

### Local Google Fonts

To improve performance and avoid CDN blocking, fonts are hosted locally.

#### Checking Your Fonts

1. Open FileBrowser
2. Navigate to `sites/[your-site]/html/wp-content/themes/[your-theme]/fonts/`
3. You should see:
   - `fonts.css`
   - Font files (`.woff2`, `.woff`)

#### Using Fonts

Ensure this line is at the **top** of your `style.css` or `input.css`:

```css
@import "./fonts/fonts.css";
```

Then use the font in your CSS:

```css
body {
    font-family: 'Vazirmatn', sans-serif;
}

h1, h2, h3 {
    font-family: 'Roboto', sans-serif;
}
```

Or with Tailwind:

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      fontFamily: {
        'vazir': ['Vazirmatn', 'sans-serif'],
        'roboto': ['Roboto', 'sans-serif'],
      },
    },
  },
}
```

```php
<h1 class="font-vazir text-4xl">سلام</h1>
<p class="font-roboto">Hello World</p>
```

#### Adding New Fonts

You **cannot** directly add fonts yourself. Ask your server admin to run the **Font Localizer Tool**:

```bash
sudo ./manage.sh
# Select: 5. Access Site Tools
# Select your site
# Select: 5. Localize Google Fonts
# Enter font URL
```

The admin will provide you with the font URL from [fonts.google.com](https://fonts.google.com).

---

## 📧 Email Testing (Mailpit)

### Accessing Mailpit

**URL**: `https://mail.yourdomain.com`

Mailpit catches all emails sent by your WordPress sites for testing.

### Features

- **View all emails**: See every email sent by WordPress
- **Search**: Find emails by subject, recipient, or content
- **Preview**: HTML and plain text versions
- **Download**: Save emails as `.eml` files
- **API**: Programmatic access for testing

### Testing Email Functionality

1. Trigger an email in WordPress:
   - User registration
   - Password reset
   - Contact form submission
   - WooCommerce order

2. Open Mailpit: `https://mail.yourdomain.com`

3. You should see the email appear immediately

4. Click to view:
   - Subject
   - From/To addresses
   - HTML preview
   - Plain text version
   - Headers

### Why Emails Don't Go to Real Inboxes

By default, all emails are caught by Mailpit for testing. This prevents:
- Accidentally spamming users during development
- Sending test emails to real customers
- Email delivery issues during testing

### Sending Real Emails

To send emails to real inboxes, configure an SMTP plugin:

1. Install **WP Mail SMTP** or **Easy WP SMTP**
2. Configure with your email provider:
   - Gmail
   - SendGrid
   - Mailgun
   - Amazon SES
3. Test with Mailpit first, then enable real sending

---

## 🖥️ Container Access (Advanced)

### Accessing WordPress Container

**Via CLI**:

```bash
# SSH into server
ssh user@your-server

# Access WordPress container
docker exec -it client1_wp bash

# Now you're inside the container
# Run WP-CLI commands
wp plugin list
wp user list
wp cache flush
```

**Via Portainer**:

1. Go to `https://portainer.yourdomain.com`
2. Click **Containers**
3. Find your container (e.g., `client1_wp`)
4. Click **>_ Console**
5. Select `/bin/bash`
6. Click **Connect**

### Accessing Database Container

```bash
# Access MySQL shell
docker exec -it client1_db mysql -u client1_user -p

# Enter password when prompted
# Now you can run SQL queries
SHOW DATABASES;
USE client1_db;
SHOW TABLES;
```

### Accessing Builder Container

```bash
# Access Node.js environment
docker exec -it client1_builder sh

# Check Node version
node --version

# Check npm packages
npm list
```

### Common WP-CLI Commands

```bash
# Inside WordPress container

# List plugins
wp plugin list

# Activate plugin
wp plugin activate plugin-name

# Update WordPress
wp core update

# Create user
wp user create john john@example.com --role=administrator

# Search and replace
wp search-replace 'oldurl.com' 'newurl.com'

# Clear cache
wp cache flush

# Regenerate thumbnails
wp media regenerate

# Export database
wp db export backup.sql

# Import database
wp db import backup.sql
```

---

## ❓ Troubleshooting

### Can't Access phpMyAdmin

**Check**:
1. Is the URL correct? `https://pma.yourdomain.com`
2. Is Traefik running? `docker ps | grep traefik`
3. Is phpMyAdmin running? `docker ps | grep pma`

**Solution**:
```bash
# Restart phpMyAdmin
docker restart shared_pma

# Check logs
docker logs shared_pma
```

### Database Connection Error

**Symptoms**: "Error establishing database connection"

**Check**:
1. Is database container running?
   ```bash
   docker ps | grep client1_db
   ```

2. Are credentials correct?
   ```bash
   cat /opt/wp-hosting/sites/client1/.env | grep DB_
   ```

**Solution**:
```bash
# Restart database
docker restart client1_db

# Restart WordPress
docker restart client1_wp
```

### CSS Not Updating

**Check**:
1. Is builder container running?
   ```bash
   docker ps | grep client1_builder
   ```

2. Are you editing the right file?
   - Edit `input.css` or `style.css`
   - NOT `output.css` (auto-generated)

**Solution**:
```bash
# Restart builder
docker restart client1_builder

# Force rebuild
docker exec client1_builder npm run build

# Hard refresh browser
Ctrl + F5 (Windows) or Cmd + Shift + R (Mac)
```

### Can't Install Plugins/Themes

**Symptoms**: "Could not create directory" error

**Cause**: File permission issues

**Solution**:
```bash
# Fix permissions
sudo chown -R client1:client1 /opt/wp-hosting/sites/client1/html/wp-content/

# Restart WordPress
docker restart client1_wp
```

### Emails Not Appearing in Mailpit

**Check**:
1. Is Mailpit running?
   ```bash
   docker ps | grep mailpit
   ```

2. Is WordPress configured to use Mailpit?
   ```bash
   docker exec client1_wp cat wp-config.php | grep SMTP
   ```

**Solution**:
```bash
# Restart Mailpit
docker restart shared_mailpit

# Check Mailpit logs
docker logs shared_mailpit
```

---

## 🔒 Security Best Practices

### Database Access

- **Never share** database credentials publicly
- **Use strong passwords** for database users
- **Limit access** to phpMyAdmin (IP whitelist if possible)
- **Regular backups** before making database changes

### File Management

- **Don't edit** core WordPress files
- **Use child themes** for customization
- **Backup** before major changes
- **Test** changes on staging first

### Container Access

- **Minimize** direct container access
- **Use WP-CLI** instead of manual database edits
- **Document** any manual changes
- **Coordinate** with your admin

---

## 📚 Additional Resources

### WordPress Documentation

- [WordPress Codex](https://codex.wordpress.org/)
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/)
- [Theme Development](https://developer.wordpress.org/themes/)

### Development Tools

- [Tailwind CSS Docs](https://tailwindcss.com/docs)
- [Lucide Icons](https://lucide.dev/icons)
- [Google Fonts](https://fonts.google.com/)

### Server Tools

- [Docker Documentation](https://docs.docker.com/)
- [Portainer Docs](https://docs.portainer.io/)
- [FileBrowser Docs](https://filebrowser.org/)

---

## 🆘 Getting Help

If you encounter issues:

1. **Check this documentation** first
2. **Check container logs**:
   ```bash
   docker logs client1_wp
   docker logs client1_db
   docker logs client1_builder
   ```
3. **Contact your server administrator**
4. **Check WordPress debug log**:
   - `sites/[your-site]/html/wp-content/debug.log`

---

## Quick Reference

### Important URLs

| Service | URL |
|---------|-----|
| **phpMyAdmin** | `https://pma.yourdomain.com` |
| **FileBrowser** | `https://files.yourdomain.com` |
| **Mailpit** | `https://mail.yourdomain.com` |
| **Portainer** | `https://portainer.yourdomain.com` |

### Common Paths

```
/opt/wp-hosting/sites/[site]/html/           # WordPress root
/opt/wp-hosting/sites/[site]/.env            # Configuration
/opt/wp-hosting/sites/[site]/backups/        # Database dumps
```

### Container Names

```
[site]_wp        # WordPress + PHP
[site]_db        # MySQL database
[site]_builder   # Node.js + Tailwind
```
