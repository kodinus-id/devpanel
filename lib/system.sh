#!/bin/bash

# Reset all configurations of the DevPanel program.
# This function will reset all configurations of the webserver, dnsmasq, MySQL, PostgreSQL, and Redis.
# It will ask for confirmation before starting the reset process.
# The reset process includes:
#   1. Removing all webserver configurations (nginx)
#   2. Resetting dnsmasq to its default configuration
#   3. Dropping all MySQL databases
#   4. Dropping all PostgreSQL databases
#   5. Flushing all Redis databases
reset_all() {
  log_action "INFO" "Resetting all configurations"
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

# Quick status check
#
# This function checks the status of all services, disk space, and memory usage.
# It will display a message with the status of each service, disk space, and memory usage.
# If any of the services are not running, disk space is above 90%, or memory usage is above 90%, it will display a warning message.
# Otherwise, it will display a success message.
quick_status_check() {
  log_action "INFO" "Quick status check"
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

# Reload all configurations of all services.
# This function will reload the configurations of all services
# that support reloading. It will show a message box with
# the results of the reload operation.
#
# Parameters: None
#
# Returns: None
reload_all_configs() {
  log_action "INFO" "Reloading all configs"
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

# Backup all configurations of DevPanel to a directory
# This function backs up all configurations of Devpanel to a directory.
# The directory will contain the site configurations, nginx configurations,
# and this info file.
#
# To restore:
# 1. Stop services if needed
# 2. Copy configurations back to their original locations
# 3. Reload/restart services
backup_configurations() {
  log_action "INFO" "Backing up configurations"
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

# Menampilkan informasi tentang sistem yang sedang berjalan,
# termasuk status layanan, jumlah situs web yang diaktifkan,
# sumber daya sistem, direktori konfigurasi, dan informasi
# tentang layanan dnsmasq.
show_system_info() {
  log_action "INFO" "Showing system info"
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

