#!/bin/bash

# Manage services menu
# - Show all services status
# - Start all services
# - Stop all services
# - Restart all services
# - Enable all services (auto-start)
# - Disable all services (manual-start)
# - Manage individual services
manage_services() {
  log_action "INFO" "Open service management menu"
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

# Mengembalikan nama layanan yang tersedia untuk dikelola.
# Fungsi ini akan mengembalikan nama layanan yang tersedia
# untuk dikelola. Nama layanan yang tidak tersedia akan
# diabaikan.
#
# Contoh:
#   services=($(get_service_names))
#   for service in "${services[@]}"; do
#     echo "$service"
#   done
get_service_names() {
  log_action "INFO" "Fetching service names"
  # Definisi layanan yang akan dikelola
  services=("nginx" "mysql" "redis-server" "postgresql")
  
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

# Resolve actual systemd unit names for known services.
# Returns 0 and prints the unit name (without .service suffix) when found,
# otherwise returns 1.
resolve_service_unit() {
  local base="$1"

  case "$base" in
    nginx)
      echo "nginx"
      return 0
      ;;
    mysql)
      if systemctl list-unit-files mysql.service >/dev/null 2>&1; then
        echo "mysql"
        return 0
      elif systemctl list-unit-files mariadb.service >/dev/null 2>&1; then
        echo "mariadb"
        return 0
      fi
      ;;
    redis)
      if systemctl list-unit-files redis.service >/dev/null 2>&1; then
        echo "redis"
        return 0
      elif systemctl list-unit-files redis-server.service >/dev/null 2>&1; then
        echo "redis-server"
        return 0
      fi
      ;;
    postgresql)
      if systemctl list-unit-files postgresql.service >/dev/null 2>&1; then
        echo "postgresql"
        return 0
      else
        local pg_service
        pg_service=$(systemctl list-unit-files "postgresql@*.service" 2>/dev/null | awk 'NR>1 {print $1}' | head -n1)
        if [[ -n "$pg_service" ]]; then
          echo "${pg_service%.service}"
          return 0
        fi
      fi
      ;;
  esac

  if systemctl list-unit-files "$base.service" >/dev/null 2>&1; then
    echo "$base"
    return 0
  fi

  return 1
}

# Helper to run systemctl action for a service and show dialog feedback.
perform_service_action() {
  local base="$1"
  local systemctl_action="$2"
  local action_desc="$3"

  local service_unit
  if ! service_unit=$(resolve_service_unit "$base"); then
    show_msg "Error" "Layanan $base tidak ditemukan di sistem."
    return 1
  fi

  if sudo systemctl "$systemctl_action" "$service_unit" 2>/dev/null; then
    show_msg "Berhasil" "Layanan $service_unit berhasil $action_desc."
    return 0
  else
    show_msg "Error" "Gagal $action_desc layanan $service_unit."
    return 1
  fi
}

# Public helpers for common service actions.
service_reload() {
  perform_service_action "$1" "reload" "direload"
}

service_restart() {
  perform_service_action "$1" "restart" "direstart"
}

# Menampilkan status semua layanan yang tersedia.
# Fungsi ini akan menampilkan status dari setiap layanan
# yang tersedia, termasuk status aktif dan status
# boot-nya.
show_all_services_status() {
  log_action "INFO" "Show all services status"
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

# Start all available services.
# 
# This function starts all available services. It prompts the user to confirm
# the action, and then iterates over all available services and attempts to
# start each one. The result of each attempt is stored in a list, and
# then displayed to the user in a message box.
start_all_services() {
  log_action "INFO" "Starting all services"
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

# Stop all available services.
# 
# This function stops all available services. It prompts the user to confirm
# the action, and then iterates over all available services and attempts to
# stop each one. The result of each attempt is stored in a list, and
# then displayed to the user in a message box.
stop_all_services() {
  log_action "INFO" "Stopping all services"
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

# Restart all available services.
# 
# This function restarts all available services. It prompts the user to confirm
# the action, and then iterates over all available services and attempts to
# restart each one. The result of each attempt is stored in a list, and
# then displayed to the user in a message box.
restart_all_services() {
  log_action "INFO" "Restarting all services"
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

# Enable all available services.
# 
# This function enables all available services. It prompts the user to confirm
# the action, and then iterates over all available services and attempts to
# enable each one. The result of each attempt is stored in a list, and
# then displayed to the user in a message box.
enable_all_services() {
  log_action "INFO" "Enabling all services"
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

# Disable all available services.
#
# This function disables all available services. It prompts the user to confirm
# the action, and then iterates over all available services and attempts to
# disable each one. The result of each attempt is stored in a list, and
# then displayed to the user in a message box.
disable_all_services() {
  log_action "INFO" "Disabling all services"
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

# Manage individual services.
#
# This function provides a menu for managing individual services.
# The menu options are:
#   1. Start service
#   2. Stop service
#   3. Restart service
#   4. Reload service
#   5. Enable (Auto-start)
#   6. Disable (Manual-start)
#   7. Status Detail
#   0. Kembali
#
# The function will display a list of available services, and then prompt
# the user to select a service to manage. Once a service is selected,
# the function will display a menu with the above options, and then perform
# the selected action. The result of the action will be displayed in a
# message box.
manage_individual_services() {
  log_action "INFO" "Manage individual service"
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

