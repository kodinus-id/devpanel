#!/bin/bash

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

get_service_names() {
  log_action "INFO" "Fetching service names"
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

