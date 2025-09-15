#!/bin/bash

# Setup direktori metadata
DEVPANEL_DIR="$HOME/.devpanel"
SITEDB="$DEVPANEL_DIR/sites"
LOGFILE="$HOME/.devpanel/panel-data.log"
mkdir -p "$SITEDB"
DNSMASQ_DEV_CONF="/etc/dnsmasq.d/devpanel.conf"

mkdir -p "$SITEDB"

hash_id() { echo -n "$1" | md5sum | awk '{print $1}'; }

log_action() {
  # Format: [2025-09-15 08:12:34] [INFO] Pesan log
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

show_msg() {
  dialog --title "$1" --msgbox "$2" 20 70
  log_action "$1 - $2"
}

reset_all() {
  dialog --yesno "⚠️ PERINGATAN ⚠️\n\nIni akan menghapus SEMUA konfigurasi project, reset DNSMasq, dan menghapus semua database (MySQL, PostgreSQL, Redis).\n\nLANJUTKAN?" 15 60 || return

  dialog --infobox "Mereset semua konfigurasi..." 5 40

  # 1. Reset Webserver
  sudo rm -f /etc/nginx/sites-enabled/*.conf
  sudo rm -f /etc/nginx/sites-available/*.conf
  sudo rm -f /etc/nginx/conf.d/*.conf
  rm -f "$SITEDB"/*.site
  sudo nginx -t 2>/dev/null && sudo systemctl reload nginx

  # 2. Reset dnsmasq
  if [[ -n "$DNSMASQ_DEV_CONF" ]]; then
    sudo rm -f "$DNSMASQ_DEV_CONF"
    sudo systemctl restart dnsmasq
  fi

  # 3. Reset MySQL
  DBS=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|mysql|information_schema|performance_schema|sys)")
  for db in $DBS; do
    mysql -u root -p -e "DROP DATABASE \`$db\`;" 2>/dev/null
  done

  # 4. Reset PostgreSQL
  PGS=$(sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres','template0','template1');" 2>/dev/null)
  for db in $PGS; do
    sudo -u postgres dropdb "$db" 2>/dev/null
  done

  # 5. Reset Redis
  redis-cli FLUSHALL >/dev/null 2>&1

  show_msg "Reset Selesai" "Semua konfigurasi webserver, dnsmasq, dan database berhasil direset."
}

# ========= FUNGSI DNSMASQ =========
manage_dnsmasq() {
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen dnsmasq" --menu "Pilih aksi:" 20 70 10 \
      1 "Status dnsmasq" \
      2 "Start dnsmasq" \
      3 "Stop dnsmasq" \
      4 "Restart dnsmasq" \
      5 "Edit Konfigurasi" \
      6 "Lihat Log" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        status=$(systemctl is-active dnsmasq 2>/dev/null)
        enabled=$(systemctl is-enabled dnsmasq 2>/dev/null)
        show_msg "Status dnsmasq" "Status: $status\nBoot: $enabled"
        ;;
      2)
        if sudo systemctl start dnsmasq; then
          show_msg "Berhasil" "dnsmasq berhasil dimulai."
        else
          show_msg "Error" "Gagal memulai dnsmasq."
        fi
        ;;
      3)
        if sudo systemctl stop dnsmasq; then
          show_msg "Berhasil" "dnsmasq berhasil dihentikan."
        else
          show_msg "Error" "Gagal menghentikan dnsmasq."
        fi
        ;;
      4)
        if sudo systemctl restart dnsmasq; then
          show_msg "Berhasil" "dnsmasq berhasil direstart."
        else
          show_msg "Error" "Gagal merestart dnsmasq."
        fi
        ;;
      5)
        cfg="/etc/dnsmasq.conf"
        sudo cp "$cfg" "$cfg.backup.$(date +%Y%m%d%H%M%S)"
        dialog --editbox "$cfg" 30 100 2> /tmp/dnsmasq_edit.tmp
        if [ -s /tmp/dnsmasq_edit.tmp ]; then
          sudo cp /tmp/dnsmasq_edit.tmp "$cfg"
          if sudo systemctl restart dnsmasq; then
            show_msg "Berhasil" "Konfigurasi dnsmasq diperbarui & service direstart."
          else
            sudo mv "$cfg.backup" "$cfg"
            show_msg "Error" "Konfigurasi gagal, dikembalikan ke backup."
          fi
        fi
        ;;
      6)
        logs=$(sudo journalctl -u dnsmasq --no-pager -n 50)
        show_msg "Log dnsmasq" "$logs"
        ;;
      0) break ;;
    esac
  done
}

update_dnsmasq_config() {
  # Regenerasi konfigurasi dnsmasq untuk semua proyek enabled
  sudo bash -c "echo '# DevPanel managed domains' > $DNSMASQ_DEV_CONF"
  
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    
    if [[ "$STATUS" == "enabled" ]]; then
      # Ambil semua domain, pisah koma
      IFS=',' read -ra domains <<< "$DOMAIN"
      for d in "${domains[@]}"; do
        d=$(echo "$d" | xargs) # trim spasi
        [[ -n "$d" ]] && echo "address=/$d/127.0.0.1" | sudo tee -a "$DNSMASQ_DEV_CONF" >/dev/null
      done
    fi
  done
  
  # Restart dnsmasq supaya config baru aktif
  sudo systemctl restart dnsmasq
}

# ========= FUNGSI SERVICE MANAGEMENT =========
manage_services() {
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen Layanan" --menu "Pilih aksi:" 20 70 10 \
      1 "Status Semua Layanan" \
      2 "Start Semua Layanan" \
      3 "Stop Semua Layanan" \
      4 "Restart Semua Layanan" \
      5 "Enable Semua Layanan (Auto-start)" \
      6 "Disable Semua Layanan (Manual-start)" \
      7 "Kelola Layanan Individual" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        show_all_services_status
        ;;
      2)
        start_all_services
        ;;
      3)
        stop_all_services
        ;;
      4)
        restart_all_services
        ;;
      5)
        enable_all_services
        ;;
      6)
        disable_all_services
        ;;
      7)
        manage_individual_services
        ;;
      0) break ;;
    esac
  done
}

get_service_names() {
  # Definisi layanan yang akan dikelola
  services=("nginx" "mysql" "redis-server" "postgresql" "dnsmasq")
  
  # Check alternatif nama service untuk kompatibilitas distro
  available_services=()
  
  for service in "${services[@]}"; do
    if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
      available_services+=("$service")
    elif [[ "$service" == "redis-server" ]] && systemctl list-unit-files "redis.service" >/dev/null 2>&1; then
      available_services+=("redis")
    elif [[ "$service" == "postgresql" ]] && systemctl list-unit-files "postgresql@*.service" >/dev/null 2>&1; then
      # Cari versi postgresql yang terinstall
      pg_service=$(systemctl list-unit-files "postgresql@*.service" 2>/dev/null | grep -o 'postgresql@[0-9]*' | head -1)
      [[ -n "$pg_service" ]] && available_services+=("$pg_service")
    fi
  done
  
  echo "${available_services[@]}"
}

show_all_services_status() {
  services=($(get_service_names))
  
  STATUS_INFO="STATUS LAYANAN\n"
  STATUS_INFO+="================\n\n"
  
  for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null)
    enabled=$(systemctl is-enabled "$service" 2>/dev/null)
    
    case "$status" in
      "active") status_text="🟢 Aktif" ;;
      "inactive") status_text="🔴 Tidak Aktif" ;;
      "failed") status_text="❌ Gagal" ;;
      *) status_text="❓ Tidak Diketahui" ;;
    esac
    
    case "$enabled" in
      "enabled") enabled_text="✅ Auto-start" ;;
      "disabled") enabled_text="❌ Manual-start" ;;
      *) enabled_text="❓ Tidak Diketahui" ;;
    esac
    
    STATUS_INFO+="$service:\n"
    STATUS_INFO+="  Status: $status_text\n"
    STATUS_INFO+="  Boot: $enabled_text\n\n"
  done
  
  show_msg "Status Layanan" "$STATUS_INFO"
}

start_all_services() {
  services=($(get_service_names))
  
  dialog --infobox "Memulai semua layanan..." 5 40
  
  results=()
  for service in "${services[@]}"; do
    if sudo systemctl start "$service" 2>/dev/null; then
      results+=("✅ $service: Berhasil dimulai")
    else
      results+=("❌ $service: Gagal dimulai")
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Hasil Start Layanan" "$result_text"
}

stop_all_services() {
  services=($(get_service_names))
  
  dialog --yesno "Yakin ingin menghentikan semua layanan?\n\nLayanan yang akan dihentikan:\n- $(echo "${services[@]}" | tr ' ' '\n- ')" 15 60 || return
  
  dialog --infobox "Menghentikan semua layanan..." 5 40
  
  results=()
  for service in "${services[@]}"; do
    if sudo systemctl stop "$service" 2>/dev/null; then
      results+=("✅ $service: Berhasil dihentikan")
    else
      results+=("❌ $service: Gagal dihentikan")
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Hasil Stop Layanan" "$result_text"
}

restart_all_services() {
  services=($(get_service_names))
  
  dialog --infobox "Merestart semua layanan..." 5 40
  
  results=()
  for service in "${services[@]}"; do
    if sudo systemctl restart "$service" 2>/dev/null; then
      results+=("✅ $service: Berhasil direstart")
    else
      results+=("❌ $service: Gagal direstart")
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Hasil Restart Layanan" "$result_text"
}

enable_all_services() {
  services=($(get_service_names))
  
  dialog --infobox "Mengaktifkan auto-start untuk semua layanan..." 5 50
  
  results=()
  for service in "${services[@]}"; do
    if sudo systemctl enable "$service" 2>/dev/null; then
      results+=("✅ $service: Auto-start diaktifkan")
    else
      results+=("❌ $service: Gagal mengaktifkan auto-start")
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Hasil Enable Layanan" "$result_text"
}

disable_all_services() {
  services=($(get_service_names))
  
  dialog --yesno "Yakin ingin menonaktifkan auto-start semua layanan?\n\nLayanan tidak akan otomatis dimulai saat boot.\n\nLayanan:\n- $(echo "${services[@]}" | tr ' ' '\n- ')" 15 60 || return
  
  dialog --infobox "Menonaktifkan auto-start untuk semua layanan..." 5 50
  
  results=()
  for service in "${services[@]}"; do
    if sudo systemctl disable "$service" 2>/dev/null; then
      results+=("✅ $service: Auto-start dinonaktifkan")
    else
      results+=("❌ $service: Gagal menonaktifkan auto-start")
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Hasil Disable Layanan" "$result_text"
}

manage_individual_services() {
  services=($(get_service_names))
  
  # Build menu options
  options=()
  for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null)
    case "$status" in
      "active") status_icon="🟢" ;;
      "inactive") status_icon="🔴" ;;
      "failed") status_icon="❌" ;;
      *) status_icon="❓" ;;
    esac
    options+=("$service" "$status_icon $service ($status)")
  done
  
  if [ ${#options[@]} -eq 0 ]; then
    show_msg "Info" "Tidak ada layanan yang tersedia."
    return
  fi
  
  selected_service=$(dialog --menu "Pilih layanan untuk dikelola:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return
  
  # Menu aksi untuk layanan terpilih
  while true; do
    status=$(systemctl is-active "$selected_service" 2>/dev/null)
    enabled=$(systemctl is-enabled "$selected_service" 2>/dev/null)
    
    ACTION_CHOICE=$(dialog --clear --title "Kelola Layanan: $selected_service" \
      --menu "Status: $status | Boot: $enabled\n\nPilih aksi:" 20 60 8 \
      1 "Start" \
      2 "Stop" \
      3 "Restart" \
      4 "Reload" \
      5 "Enable (Auto-start)" \
      6 "Disable (Manual-start)" \
      7 "Status Detail" \
      0 "Kembali" \
      3>&1 1>&2 2>&3) || break
      
    case $ACTION_CHOICE in
      1)
        if sudo systemctl start "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Layanan $selected_service berhasil dimulai."
        else
          show_msg "Error" "Gagal memulai layanan $selected_service."
        fi
        ;;
      2)
        if sudo systemctl stop "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Layanan $selected_service berhasil dihentikan."
        else
          show_msg "Error" "Gagal menghentikan layanan $selected_service."
        fi
        ;;
      3)
        if sudo systemctl restart "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Layanan $selected_service berhasil direstart."
        else
          show_msg "Error" "Gagal merestart layanan $selected_service."
        fi
        ;;
      4)
        if sudo systemctl reload "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Layanan $selected_service berhasil direload."
        else
          show_msg "Error" "Gagal mereload layanan $selected_service."
        fi
        ;;
      5)
        if sudo systemctl enable "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Auto-start untuk $selected_service berhasil diaktifkan."
        else
          show_msg "Error" "Gagal mengaktifkan auto-start untuk $selected_service."
        fi
        ;;
      6)
        if sudo systemctl disable "$selected_service" 2>/dev/null; then
          show_msg "Berhasil" "Auto-start untuk $selected_service berhasil dinonaktifkan."
        else
          show_msg "Error" "Gagal menonaktifkan auto-start untuk $selected_service."
        fi
        ;;
      7)
        detail_status=$(sudo systemctl status "$selected_service" 2>/dev/null | head -20)
        show_msg "Status Detail: $selected_service" "$detail_status"
        ;;
      0) break ;;
    esac
  done
}

# ========= FUNGSI WEB SERVER =========
manage_webserver() {
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

# ========= FUNGSI MYSQL =========
manage_mysql() {
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen MySQL" --menu "Pilih aksi:" 20 70 10 \
      1 "Daftar Database & User" \
      2 "Tambah Database" \
      3 "Hapus Database" \
      4 "Tambah User" \
      5 "Hapus User" \
      6 "Grant Privileges" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        DBS=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null)
        USERS=$(mysql -u root -p -e "SELECT User, Host FROM mysql.user;" 2>/dev/null)
        show_msg "Daftar MySQL" "Databases:\n$DBS\n\nUsers:\n$USERS"
        ;;
      2)
        db=$(dialog --inputbox "Nama Database:" 10 50 3>&1 1>&2 2>&3) || continue
        if mysql -u root -p -e "CREATE DATABASE \`$db\`;" 2>/dev/null; then
          show_msg "Berhasil" "Database $db berhasil dibuat."
        else
          show_msg "Error" "Gagal membuat database $db."
        fi
        ;;
      3)
        db=$(dialog --inputbox "Database yang akan dihapus:" 10 50 3>&1 1>&2 2>&3) || continue
        dialog --yesno "Yakin ingin menghapus database '$db'?" 10 50 || continue
        if mysql -u root -p -e "DROP DATABASE \`$db\`;" 2>/dev/null; then
          show_msg "Berhasil" "Database $db berhasil dihapus."
        else
          show_msg "Error" "Gagal menghapus database $db."
        fi
        ;;
      4)
        user=$(dialog --inputbox "Username:" 10 50 3>&1 1>&2 2>&3) || continue
        pass=$(dialog --passwordbox "Password:" 10 50 3>&1 1>&2 2>&3) || continue
        if mysql -u root -p -e "CREATE USER '$user'@'localhost' IDENTIFIED BY '$pass';" 2>/dev/null; then
          show_msg "Berhasil" "User $user berhasil dibuat."
        else
          show_msg "Error" "Gagal membuat user $user."
        fi
        ;;
      5)
        user=$(dialog --inputbox "User yang akan dihapus:" 10 50 3>&1 1>&2 2>&3) || continue
        dialog --yesno "Yakin ingin menghapus user '$user'?" 10 50 || continue
        if mysql -u root -p -e "DROP USER '$user'@'localhost';" 2>/dev/null; then
          show_msg "Berhasil" "User $user berhasil dihapus."
        else
          show_msg "Error" "Gagal menghapus user $user."
        fi
        ;;
      6)
        db=$(dialog --inputbox "Nama Database:" 10 50 3>&1 1>&2 2>&3) || continue
        user=$(dialog --inputbox "Username:" 10 50 3>&1 1>&2 2>&3) || continue
        if mysql -u root -p -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$user'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null; then
          show_msg "Berhasil" "Privileges berhasil diberikan ke user $user untuk database $db."
        else
          show_msg "Error" "Gagal memberikan privileges."
        fi
        ;;
      0) break ;;
    esac
  done
}

# ========= FUNGSI REDIS =========
manage_redis() {
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen Redis" --menu "Pilih aksi:" 15 60 6 \
      1 "Info Database" \
      2 "Flush Semua Database" \
      3 "Flush Database Aktif" \
      4 "Monitor Redis" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1) 
        INFO=$(redis-cli INFO keyspace 2>/dev/null | grep db)
        show_msg "Redis Info" "${INFO:-Tidak ada data}"
        ;;
      2) 
        dialog --yesno "Yakin ingin menghapus SEMUA database Redis?" 10 50 || continue
        redis-cli FLUSHALL >/dev/null 2>&1
        show_msg "Berhasil" "Semua database Redis berhasil dihapus."
        ;;
      3) 
        dialog --yesno "Yakin ingin menghapus database Redis yang aktif?" 10 50 || continue
        redis-cli FLUSHDB >/dev/null 2>&1
        show_msg "Berhasil" "Database Redis aktif berhasil dihapus."
        ;;
      4)
        show_msg "Info" "Redis Monitor akan berjalan di terminal.\nTekan Ctrl+C untuk keluar dari monitor."
        clear
        redis-cli MONITOR
        ;;
      0) break ;;
    esac
  done
}

# ========= FUNGSI POSTGRES =========
manage_postgres() {
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen PostgreSQL" --menu "Pilih aksi:" 20 70 10 \
      1 "Daftar Database & User" \
      2 "Tambah Database" \
      3 "Hapus Database" \
      4 "Tambah User" \
      5 "Hapus User" \
      6 "Grant Privileges" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        DBS=$(sudo -u postgres psql -c "\l" 2>/dev/null)
        USERS=$(sudo -u postgres psql -c "\du" 2>/dev/null)
        show_msg "Daftar PostgreSQL" "Databases:\n$DBS\n\nUsers:\n$USERS"
        ;;
      2) 
        db=$(dialog --inputbox "Nama Database:" 10 50 3>&1 1>&2 2>&3) || continue
        if sudo -u postgres createdb "$db" 2>/dev/null; then
          show_msg "Berhasil" "Database $db berhasil dibuat."
        else
          show_msg "Error" "Gagal membuat database $db."
        fi
        ;;
      3) 
        db=$(dialog --inputbox "Database yang akan dihapus:" 10 50 3>&1 1>&2 2>&3) || continue
        dialog --yesno "Yakin ingin menghapus database '$db'?" 10 50 || continue
        if sudo -u postgres dropdb "$db" 2>/dev/null; then
          show_msg "Berhasil" "Database $db berhasil dihapus."
        else
          show_msg "Error" "Gagal menghapus database $db."
        fi
        ;;
      4) 
        user=$(dialog --inputbox "Username:" 10 50 3>&1 1>&2 2>&3) || continue
        pass=$(dialog --passwordbox "Password:" 10 50 3>&1 1>&2 2>&3) || continue
        if sudo -u postgres psql -c "CREATE USER $user WITH PASSWORD '$pass';" 2>/dev/null; then
          show_msg "Berhasil" "User $user berhasil dibuat."
        else
          show_msg "Error" "Gagal membuat user $user."
        fi
        ;;
      5) 
        user=$(dialog --inputbox "User yang akan dihapus:" 10 50 3>&1 1>&2 2>&3) || continue
        dialog --yesno "Yakin ingin menghapus user '$user'?" 10 50 || continue
        if sudo -u postgres psql -c "DROP USER $user;" 2>/dev/null; then
          show_msg "Berhasil" "User $user berhasil dihapus."
        else
          show_msg "Error" "Gagal menghapus user $user."
        fi
        ;;
      6) 
        db=$(dialog --inputbox "Nama Database:" 10 50 3>&1 1>&2 2>&3) || continue
        user=$(dialog --inputbox "Username:" 10 50 3>&1 1>&2 2>&3) || continue
        if sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db TO $user;" 2>/dev/null; then
          show_msg "Berhasil" "Privileges berhasil diberikan ke user $user untuk database $db."
        else
          show_msg "Error" "Gagal memberikan privileges."
        fi
        ;;
      0) break ;;
    esac
  done
}

# ========= PANEL UTAMA =========
main_menu() {
  while true; do
    MAIN_CHOICE=$(dialog --clear --title "Dev Service Panel v2.2" --menu "Pilih menu:" 20 70 12 \
      1 "Manajemen Layanan" \
      2 "Manajemen Webserver" \
      3 "Manajemen MySQL" \
      4 "Manajemen Redis" \
      5 "Manajemen PostgreSQL" \
      6 "Manajemen dnsmasq" \
      7 "Informasi Sistem" \
      8 "Aksi Cepat" \
      9 "Atur Ulang Semua Konfigurasi" \
      0 "Keluar" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && exit

    case $MAIN_CHOICE in
      1) manage_services ;;
      2) manage_webserver ;;
      3) manage_mysql ;;
      4) manage_redis ;;
      5) manage_postgres ;;
      6) manage_dnsmasq ;;   # <== ini tambahan
      7) show_system_info ;;
      8) quick_actions ;;
      9) reset_all ;;
      0) clear; echo "Terima kasih telah menggunakan Dev Panel!"; exit 0 ;;
    esac
  done
}

# ========= QUICK ACTIONS =========
quick_actions() {
  while true; do
    CHOICE=$(dialog --clear --title "Quick Actions" --menu "Aksi cepat:" 18 60 8 \
      1 "🟢 Start All Services" \
      2 "🔴 Stop All Services" \
      3 "🔄 Restart All Services" \
      4 "📊 Quick Status Check" \
      5 "🔧 Reload All Configs" \
      6 "💾 Backup Configurations" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        start_all_services
        ;;
      2)
        stop_all_services
        ;;
      3)
        restart_all_services
        ;;
      4)
        quick_status_check
        ;;
      5)
        reload_all_configs
        ;;
      6)
        backup_configurations
        ;;
      0) break ;;
    esac
  done
}

quick_status_check() {
  services=($(get_service_names))
  
  STATUS_INFO="QUICK STATUS CHECK\n"
  STATUS_INFO+="==================\n\n"
  
  all_good=true
  
  for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null)
    
    if [[ "$status" == "active" ]]; then
      STATUS_INFO+="$service: Running\n"
    else
      STATUS_INFO+="$service: Not Running\n"
      all_good=false
    fi
  done
  
  STATUS_INFO+="\n"
  
  # Check disk space
  disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  if [ "$disk_usage" -gt 90 ]; then
    STATUS_INFO+="Disk Usage: ${disk_usage}% (WARNING)\n"
    all_good=false
  else
    STATUS_INFO+="Disk Usage: ${disk_usage}% (OK)\n"
  fi
  
  # Check memory
  mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2 }')
  if [ "$mem_usage" -gt 90 ]; then
    STATUS_INFO+="Memory Usage: ${mem_usage}% (WARNING)\n"
    all_good=false
  else
    STATUS_INFO+="Memory Usage: ${mem_usage}% (OK)\n"
  fi
  
  STATUS_INFO+="\n"
  
  if $all_good; then
    STATUS_INFO+="All systems operational!"
  else
    STATUS_INFO+="Some issues detected!"
  fi
  
  show_msg "Quick Status" "$STATUS_INFO"
}

reload_all_configs() {
  services=($(get_service_names))
  
  dialog --infobox "Reloading configurations..." 5 40
  
  results=()
  
  # Reload nginx
  if systemctl is-active nginx >/dev/null 2>&1; then
    if sudo nginx -t 2>/dev/null && sudo systemctl reload nginx 2>/dev/null; then
      results+=("Nginx: Configuration reloaded")
    else
      results+=("Nginx: Failed to reload configuration")
    fi
  fi
  
  # Reload other services that support reload
  for service in "${services[@]}"; do
    if [[ "$service" != "nginx" ]] && systemctl is-active "$service" >/dev/null 2>&1; then
      if sudo systemctl reload "$service" 2>/dev/null; then
        results+=("$service: Configuration reloaded")
      else
        results+=("$service: Reload not supported or failed")
      fi
    fi
  done
  
  result_text=$(printf "%s\n" "${results[@]}")
  show_msg "Reload Results" "$result_text"
}

backup_configurations() {
  backup_dir="$HOME/devpanel-backup-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"
  
  dialog --infobox "Creating backup..." 5 30
  
  # Backup site configurations
  if [ -d "$SITEDB" ]; then
    cp -r "$SITEDB" "$backup_dir/sites/"
  fi
  
  # Backup nginx configs (only our managed sites)
  mkdir -p "$backup_dir/nginx"
  shopt -s nullglob
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    id=$(basename "$f" .site)
    if [ -f "/etc/nginx/sites-available/$id.conf" ]; then
      sudo cp "/etc/nginx/sites-available/$id.conf" "$backup_dir/nginx/" 2>/dev/null
    fi
  done
  
  # Create backup info
  cat <<BACKUP_INFO > "$backup_dir/backup_info.txt"
DevPanel Backup Information
===========================
Backup Date: $(date)
Backup Location: $backup_dir
DevPanel Version: 2.1

Contents:
- Site configurations: sites/
- Nginx configurations: nginx/
- This info file: backup_info.txt

To restore:
1. Stop services if needed
2. Copy configurations back to their original locations
3. Reload/restart services
BACKUP_INFO

  show_msg "Backup Complete" "Backup berhasil dibuat di:\n$backup_dir\n\nIsi backup:\n- Konfigurasi situs\n- Konfigurasi Nginx\n- Info backup"
}

show_system_info() {
  # Check service status dengan fallback yang lebih baik
  services=($(get_service_names))
  
  STATUS_INFO="INFORMASI SISTEM\n"
  STATUS_INFO+="==================\n\n"
  STATUS_INFO+="Status Layanan:\n"
  
  for service in "${services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null)
    enabled=$(systemctl is-enabled "$service" 2>/dev/null)
    
    case "$status" in
      "active") status_text="Aktif" ;;
      "inactive") status_text="Tidak Aktif" ;;
      "failed") status_text="Gagal" ;;
      *) status_text="Tidak Diketahui" ;;
    esac
    
    case "$enabled" in
      "enabled") boot_text=" (Auto-start)" ;;
      "disabled") boot_text=" (Manual)" ;;
      *) boot_text="" ;;
    esac
    
    STATUS_INFO+="- $service: $status_text$boot_text\n"
  done
  
  TOTAL_SITES=$(find "$SITEDB" -name "*.site" 2>/dev/null | wc -l)
  ENABLED_SITES=$(grep -l 'STATUS="enabled"' "$SITEDB"/*.site 2>/dev/null | wc -l)
  
  STATUS_INFO+="\n"
  STATUS_INFO+="Proyek Situs Web:\n"
  STATUS_INFO+="- Total: $TOTAL_SITES\n"
  STATUS_INFO+="- Enabled: $ENABLED_SITES\n"
  STATUS_INFO+="- Disabled: $((TOTAL_SITES - ENABLED_SITES))\n\n"
  
  # System resources
  disk_usage=$(df -h / | awk 'NR==2 {print $5}')
  mem_total=$(free -h | awk 'NR==2{print $2}')
  mem_used=$(free -h | awk 'NR==2{print $3}')
  
  STATUS_INFO+="Sumber Daya Sistem:\n"
  STATUS_INFO+="- Disk Usage: $disk_usage\n"
  STATUS_INFO+="- Memory: $mem_used / $mem_total\n\n"
  
  STATUS_INFO+="Direktori:\n"
  STATUS_INFO+="- Config: $SITEDB\n"
  STATUS_INFO+="- Nginx Sites: /etc/nginx/sites-available/\n"
  STATUS_INFO+="- SSL Certs: /etc/ssl/local-dev/\n"
  
  STATUS_INFO+="\nDNSMasq:\n"
  if systemctl is-active dnsmasq >/dev/null 2>&1; then
    STATUS_INFO+="- dnsmasq: Aktif\n"
  else
    STATUS_INFO+="- dnsmasq: Tidak Aktif\n"
  fi
  STATUS_INFO+="- Config: $DNSMASQ_DEV_CONF\n"
  
  show_msg "System Info" "$STATUS_INFO"
}

# Check dependencies
check_dependencies() {
  missing_deps=()
  
  command -v dialog >/dev/null || missing_deps+=("dialog")
  command -v nginx >/dev/null || missing_deps+=("nginx")
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "Missing dependencies: ${missing_deps[*]}"
    echo "Please install missing packages and try again."
    echo ""
    echo "For Ubuntu/Debian:"
    echo "  sudo apt update && sudo apt install ${missing_deps[*]}"
    echo ""
    echo "For CentOS/RHEL/Fedora:"
    echo "  sudo yum install ${missing_deps[*]} # or dnf install"
    exit 1
  fi
}

# Main execution
check_dependencies
main_menu
