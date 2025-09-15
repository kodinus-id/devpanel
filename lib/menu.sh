#!/bin/bash

main_menu() {
  log_action "INFO" "Open main menu"
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
  log_action "INFO" "Open quick actions menu"
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
