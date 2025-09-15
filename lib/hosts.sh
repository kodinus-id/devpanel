#!/bin/bash

# Manage hosts file entries for local development
# Provides functions to edit /etc/hosts and regenerate
# project domain mappings.

# Open hosts management menu
manage_hosts() {
  log_action "INFO" "Open hosts management menu"
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen Hosts" --menu "Pilih aksi:" 20 70 10 \
      1 "Lihat /etc/hosts" \
      2 "Edit /etc/hosts" \
      3 "Regenerasi entri dari proyek" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        content=$(sudo cat "$HOSTS_FILE" 2>/dev/null)
        show_msg "/etc/hosts" "$content"
        ;;
      2)
        sudo cp "$HOSTS_FILE" "$HOSTS_FILE.backup.$(date +%Y%m%d%H%M%S)"
        dialog --editbox "$HOSTS_FILE" 30 100 2> /tmp/hosts_edit.tmp
        if [ -s /tmp/hosts_edit.tmp ]; then
          sudo cp /tmp/hosts_edit.tmp "$HOSTS_FILE"
          show_msg "Berhasil" "/etc/hosts diperbarui."
        fi
        ;;
      3)
        update_hosts_file
        show_msg "Berhasil" "Entri hosts diperbarui dari daftar proyek."
        ;;
      0) break ;;
    esac
  done
}

# Update hosts file with enabled project domains
update_hosts_file() {
  log_action "INFO" "Updating hosts file"
  sudo sed -i "/$HOSTS_SECTION_START/,/$HOSTS_SECTION_END/d" "$HOSTS_FILE"
  sudo bash -c "echo '$HOSTS_SECTION_START' >> $HOSTS_FILE"
  for f in "$SITEDB"/*.site; do
    [[ -f "$f" ]] || continue
    . "$f"
    if [[ "$STATUS" == "enabled" ]]; then
      IFS=',' read -ra domains <<< "$DOMAIN"
      for d in "${domains[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -n "$d" ]] && echo "127.0.0.1 $d" | sudo tee -a "$HOSTS_FILE" >/dev/null && log_action "INFO" "hosts add $d"
      done
    fi
  done
  sudo bash -c "echo '$HOSTS_SECTION_END' >> $HOSTS_FILE"
  log_action "INFO" "hosts file updated"
}

