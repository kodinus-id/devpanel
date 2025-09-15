#!/bin/bash

manage_dnsmasq() {
  log_action "INFO" "Open dnsmasq management menu"
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
          log_action "INFO" "dnsmasq started"
        else
          show_msg "Error" "Gagal memulai dnsmasq."
          log_action "ERROR" "Failed to start dnsmasq"
        fi
        ;;
      3)
        if sudo systemctl stop dnsmasq; then
          show_msg "Berhasil" "dnsmasq berhasil dihentikan."
          log_action "INFO" "dnsmasq stopped"
        else
          show_msg "Error" "Gagal menghentikan dnsmasq."
          log_action "ERROR" "Failed to stop dnsmasq"
        fi
        ;;
      4)
        if sudo systemctl restart dnsmasq; then
          show_msg "Berhasil" "dnsmasq berhasil direstart."
          log_action "INFO" "dnsmasq restarted"
        else
          show_msg "Error" "Gagal merestart dnsmasq."
          log_action "ERROR" "Failed to restart dnsmasq"
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
            log_action "INFO" "dnsmasq config updated"
          else
            sudo mv "$cfg.backup" "$cfg"
            show_msg "Error" "Konfigurasi gagal, dikembalikan ke backup."
            log_action "ERROR" "dnsmasq config update failed"
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
  log_action "INFO" "Updating dnsmasq config"
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
        log_action "INFO" "dnsmasq add $d"
      done
    fi
  done

  # Restart dnsmasq supaya config baru aktif
  sudo systemctl restart dnsmasq
  log_action "INFO" "dnsmasq config reloaded"
}
