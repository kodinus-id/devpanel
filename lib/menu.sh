#!/bin/bash

# Menampilkan menu utama panel.
# Pilihan menu:
#   1. Manajemen Layanan
#   2. Manajemen Webserver
#   3. Manajemen MySQL
#   4. Manajemen Redis
#   5. Manajemen PostgreSQL
#   6. Manajemen Hosts File
#   7. Informasi Sistem
#   8. Aksi Cepat
#   9. Atur Ulang Semua Konfigurasi
#   0. Keluar
main_menu() {
  log_action "INFO" "Open main menu"
  while true; do
    MAIN_CHOICE=$(dialog --clear --title "Dev Service Panel v2.2" --menu "Pilih menu:" 20 70 12 \
      1 "Manajemen Layanan" \
      2 "Manajemen Webserver" \
      3 "Manajemen MySQL" \
      4 "Manajemen Redis" \
      5 "Manajemen PostgreSQL" \
        6 "Manajemen Hosts" \
      7 "Informasi Sistem" \
      8 "Aksi Cepat" \
      9 "Atur Ulang Semua Konfigurasi" \
      0 "Keluar" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && exit_panel

    case $MAIN_CHOICE in
      1) manage_services ;;
      2) manage_webserver ;;
      3) manage_mysql ;;
      4) manage_redis ;;
      5) manage_postgres ;;
        6) manage_hosts ;;   # <== ini tambahan
      7) show_system_info ;;
      8) quick_actions ;;
      9) reset_all ;;
      0) exit_panel ;;
    esac
  done
}

# Membuka menu aksi cepat yang memungkinkan beberapa aksi yang sering
# digunakan untuk mempercepat proses manajemen layanan, seperti
# memulai, menghentikan, dan memuat ulang semua layanan,
# memeriksa status layanan secara singkat, memuat ulang
# konfigurasi semua layanan, dan mencadangkan konfigurasi
# semua layanan.
quick_actions() {
  log_action "INFO" "Open quick actions menu"
  while true; do
    CHOICE=$(dialog --clear --title "Quick Actions" --menu "Aksi cepat:" 18 60 8 \
      1 "Jalankan Semua Layanan" \
      2 "Berhentikan Semua Layanan" \
      3 "Muat ulang Semua Layanan" \
      4 "Pemeriksa Status Layanan Secara Singkat" \
      5 "Muat Ulang Semua Konfigurasi" \
      6 "Cadangkan Semua Konfigurasi" \
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
