#!/bin/bash

manage_webserver() {
  log_action "INFO" "Open webserver management"
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen Webserver" --menu "Pilih aksi:" 20 70 10 \
      1 "Daftar Proyek" \
      2 "Tambah Proyek" \
      3 "Edit Proyek" \
      4 "Hapus Proyek" \
      5 "Enable SSL" \
      6 "Toggle Status" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        list_projects
        ;;
      2)
        add_project
        ;;
      3)
        edit_project
        ;;
      4)
        delete_project
        ;;
      5)
        enable_ssl
        ;;
      6)
        toggle_project_status
        ;;
      0) break ;;
    esac
  done
}

list_projects() {
  log_action "INFO" "Listing projects"
  RESULT="FORMAT: [STATUS] DOMAIN | TYPE | ROOT | SSL\n"
  RESULT+="-------------------------------------------------\n"
  
  if [ ! "$(ls -A "$SITEDB"/*.site 2>/dev/null)" ]; then
    show_msg "Daftar Proyek" "Belum ada proyek yang terdaftar."
    return
  fi

  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    
    # Reset variables
    DOMAIN="" ROOT="" SSL="0" SITE_TYPE="static" STATUS="enabled"
    
    # Load site data
    . "$f"
    
    # Determine status symbol
    STATUS_SYMBOL="[✓]"
    if [[ "$STATUS" == "disabled" ]]; then
      STATUS_SYMBOL="[✗]"
    fi
    
    # Format SSL status
    SSL_STATUS="No"
    if [[ "$SSL" == "1" ]]; then
      SSL_STATUS="Yes"
    fi
    
    RESULT+="\n$STATUS_SYMBOL $DOMAIN | $SITE_TYPE | $ROOT | SSL: $SSL_STATUS"
  done
  
  show_msg "Daftar Proyek" "$RESULT"
}

add_project() {
  log_action "INFO" "Adding project"
  # Input domain
  domains=$(dialog --inputbox "Masukkan domain (pisahkan dengan koma jika multiple):" 10 70 3>&1 1>&2 2>&3) || return
  
  # Input root path
  root=$(dialog --inputbox "Path root project:" 10 70 3>&1 1>&2 2>&3) || return
  
  # Pilih tipe site
  site_type=$(dialog --clear --title "Tipe Website" --menu "Pilih tipe website:" 15 60 4 \
    "static" "Static HTML/CSS/JS" \
    "php" "PHP Application" \
    "laravel" "Laravel Framework" \
    "nodejs" "Node.js Application" \
    3>&1 1>&2 2>&3) || return

  # Generate ID dari domain
  id=$(hash_id "$domains")
  cfg="/etc/nginx/conf.d/$id.conf"

  # Buat konfigurasi nginx berdasarkan tipe
  create_nginx_config "$domains" "$root" "$site_type" "$cfg"

  # Simpan metadata
  cat <<META > "$SITEDB/$id.site"
DOMAIN="$domains"
ROOT="$root"
SITE_TYPE="$site_type"
SSL=0
STATUS="enabled"
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
META

  # Test dan reload nginx
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    update_dnsmasq_config
    show_msg "Berhasil" "Proyek $domains ($site_type) berhasil ditambahkan.\nID: $id"
  else
    # Rollback jika error
    sudo rm -f "/etc/nginx/sites-enabled/$id.conf" "/etc/nginx/sites-available/$id.conf"
    rm -f "$SITEDB/$id.site"
    show_msg "Error" "Gagal membuat konfigurasi nginx. Silakan periksa sintaks."
  fi
}

create_nginx_config() {
  log_action "INFO" "Creating nginx config"
  local domains="$(echo "$1" | tr ',' ' ')"
  local root="$2" 
  local site_type="$3"
  local cfg="$4"
  
  case "$site_type" in
    "static")
      cat <<EOF | sudo tee "$cfg" >/dev/null
server {
    listen 80;
    server_name $domains;
    root $root;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Cache static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
      ;;
    "php"|"laravel")
      local php_version="8.4"  # Bisa disesuaikan
      cat <<EOF | sudo tee "$cfg" >/dev/null
server {
    listen 80;
    server_name $domains;
    root $root;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf; 
    }
    
    # Security
    location ~ /\.ht {
        deny all;
    }
    
    # Laravel specific (jika laravel)
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
      ;;
    "nodejs")
      cat <<EOF | sudo tee "$cfg" >/dev/null
server {
    listen 80;
    server_name $domains;
    
    location / {
        proxy_pass http://localhost:3000;  # Default Node.js port
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
      ;;
  esac
}

edit_project() {
  log_action "INFO" "Editing project"
  # Pilih project untuk diedit
  options=()
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    id=$(basename "$f" .site)
    options+=("$id" "$DOMAIN ($SITE_TYPE)")
  done
  
  if [ ${#options[@]} -eq 0 ]; then
    show_msg "Info" "Tidak ada proyek untuk diedit."
    return
  fi
  
  site=$(dialog --menu "Pilih proyek untuk diedit:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return
  
  # Load current data
  . "$SITEDB/$site.site"
  
  # Edit options
  EDIT_CHOICE=$(dialog --clear --title "Edit Proyek: $DOMAIN" --menu "Pilih yang akan diedit:" 15 60 5 \
    1 "Domain" \
    2 "Root Path" \
    3 "Site Type" \
    0 "Batal" \
    3>&1 1>&2 2>&3) || return
    
  case $EDIT_CHOICE in
    1)
      new_domains=$(dialog --inputbox "Domain baru:" 10 70 "$DOMAIN" 3>&1 1>&2 2>&3) || return
      DOMAIN="$new_domains"
      ;;
    2)
      new_root=$(dialog --inputbox "Root path baru:" 10 70 "$ROOT" 3>&1 1>&2 2>&3) || return
      ROOT="$new_root"
      ;;
    3)
      new_type=$(dialog --clear --title "Tipe Website Baru" --menu "Pilih tipe:" 15 60 4 \
        "static" "Static HTML/CSS/JS" \
        "php" "PHP Application" \
        "laravel" "Laravel Framework" \
        "nodejs" "Node.js Application" \
        3>&1 1>&2 2>&3) || return
      SITE_TYPE="$new_type"
      ;;
    0) return ;;
  esac
  
  # Update nginx config
  cfg="/etc/nginx/conf.d/$site.conf"
  create_nginx_config "$DOMAIN" "$ROOT" "$SITE_TYPE" "$cfg"
  
  # Update metadata
  cat <<META > "$SITEDB/$site.site"
DOMAIN="$DOMAIN"
ROOT="$ROOT"
SITE_TYPE="$SITE_TYPE"
SSL=$SSL
STATUS="$STATUS"
CREATED="$CREATED"
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
META
  
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    show_msg "Berhasil" "Proyek berhasil diperbarui."
  else
    show_msg "Error" "Gagal memperbarui konfigurasi nginx."
  fi
}

delete_project() {
  log_action "INFO" "Deleting project"
  options=()
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    id=$(basename "$f" .site)
    options+=("$id" "$DOMAIN ($SITE_TYPE)")
  done
  
  if [ ${#options[@]} -eq 0 ]; then
    show_msg "Info" "Tidak ada proyek untuk dihapus."
    return
  fi
  
  site=$(dialog --menu "Pilih proyek yang akan dihapus:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return

  # Konfirmasi
  . "$SITEDB/$site.site"
  dialog --yesno "Yakin ingin menghapus proyek '$DOMAIN'?" 10 50 || return

  # Hapus file dan konfigurasi
  rm -f "$SITEDB/$site.site"
  sudo rm -f "/etc/nginx/sites-enabled/$site.conf" "/etc/nginx/sites-available/$site.conf"
  
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    show_msg "Berhasil" "Proyek $DOMAIN berhasil dihapus."
  else
    show_msg "Error" "Ada masalah dengan konfigurasi nginx setelah penghapusan."
  fi
}

toggle_project_status() {
  log_action "INFO" "Toggling project status"
  options=()
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    id=$(basename "$f" .site)
    status_text="enabled"
    [[ "$STATUS" == "disabled" ]] && status_text="disabled"
    options+=("$id" "$DOMAIN ($status_text)")
  done
  
  if [ ${#options[@]} -eq 0 ]; then
    show_msg "Info" "Tidak ada proyek untuk dikelola."
    return
  fi
  
  site=$(dialog --menu "Pilih proyek untuk toggle status:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return
  
  # Load current data
  . "$SITEDB/$site.site"
  
  if [[ "$STATUS" == "enabled" ]]; then
    # Disable site
    sudo rm -f "/etc/nginx/sites-enabled/$site.conf"
    new_status="disabled"
    action="dinonaktifkan"
  else
    # Enable site  
    sudo ln -s "/etc/nginx/sites-available/$site.conf" "/etc/nginx/sites-enabled/" 2>/dev/null
    new_status="enabled"
    action="diaktifkan"
  fi
  
  # Update metadata
  cat <<META > "$SITEDB/$site.site"
DOMAIN="$DOMAIN"
ROOT="$ROOT"
SITE_TYPE="$SITE_TYPE"
SSL=$SSL
STATUS="$new_status"
CREATED="$CREATED"
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
META
  
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    show_msg "Berhasil" "Proyek $DOMAIN berhasil $action."
  else
    show_msg "Error" "Ada masalah dengan konfigurasi nginx."
  fi
}

enable_ssl() {
  log_action "INFO" "Enabling SSL"
  options=()
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    id=$(basename "$f" .site)
    ssl_status="No SSL"
    [[ "$SSL" == "1" ]] && ssl_status="SSL Active"
    options+=("$id" "$DOMAIN ($ssl_status)")
  done
  
  if [ ${#options[@]} -eq 0 ]; then
    show_msg "Info" "Tidak ada proyek untuk SSL."
    return
  fi
  
  site=$(dialog --menu "Pilih proyek untuk SSL:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return
  . "$SITEDB/$site.site"

  crt=$(dialog --inputbox "Path SSL certificate (.crt/.pem):" 10 70 3>&1 1>&2 2>&3)
  key=$(dialog --inputbox "Path SSL private key (.key):" 10 70 3>&1 1>&2 2>&3)

  # Jika kosong, buat self-signed certificate
  if [[ -z "$crt" || -z "$key" ]]; then
    sudo mkdir -p /etc/ssl/local-dev
    crt="/etc/ssl/local-dev/$site.crt"
    key="/etc/ssl/local-dev/$site.key"
    
    # Extract first domain for CN
    first_domain=$(echo "$DOMAIN" | cut -d',' -f1 | tr -d ' ')
    
    sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj "/CN=$first_domain" -keyout "$key" -out "$crt" 2>/dev/null
    
    show_msg "Info" "Self-signed certificate dibuat untuk $first_domain"
  fi

  # Update nginx config dengan SSL
  cfg="/etc/nginx/conf.d/$site.conf"
  
  # Backup original config
  sudo cp "$cfg" "$cfg.backup"
  
  # Add SSL configuration
  sudo sed -i '/listen 80;/a \    listen 443 ssl;\n    http2 on;\n    ssl_certificate '"$crt"';\n    ssl_certificate_key '"$key"';\n    ssl_protocols TLSv1.2 TLSv1.3;\n    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;\n    ssl_prefer_server_ciphers off;\n    add_header Strict-Transport-Security "max-age=31536000" always;' "$cfg"

  # Test nginx config
  if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    
    # Update metadata
    cat <<META > "$SITEDB/$site.site"
DOMAIN="$DOMAIN"
ROOT="$ROOT"
SITE_TYPE="$SITE_TYPE"
SSL=1
SSL_CRT="$crt"
SSL_KEY="$key"
STATUS="$STATUS"
CREATED="$CREATED"
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
META

    show_msg "Berhasil" "SSL berhasil diaktifkan untuk $DOMAIN\nCertificate: $crt\nPrivate Key: $key"
  else
    # Restore backup
    sudo mv "$cfg.backup" "$cfg"
    show_msg "Error" "Gagal mengaktifkan SSL. Konfigurasi dikembalikan."
  fi
}

