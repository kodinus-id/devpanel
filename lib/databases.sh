#!/bin/bash

# Manage MySQL databases and users
# This function provides a menu for managing MySQL databases and users.
# It will ask for the root password, and then provide options to list
# databases and users, create a new database, delete a database,
# create a new user, delete a user, and grant privileges to a user
# for a specific database.
manage_mysql() {
  log_action "INFO" "Managing MySQL"
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen MySQL" --menu "Pilih aksi:" 20 70 12 \
      1 "Daftar Database & User" \
      2 "Tambah Database" \
      3 "Hapus Database" \
      4 "Tambah User" \
      5 "Hapus User" \
      6 "Grant Privileges" \
      7 "Reload Layanan MySQL" \
      8 "Restart Layanan MySQL" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        pass=$(dialog --passwordbox "Password root MySQL:" 10 50 3>&1 1>&2 2>&3) || continue
        DBS=$(mysql -u root -p"$pass" -N -B -e "SHOW DATABASES;" 2>/dev/null)
        USERS=$(mysql -u root -p"$pass" -N -B -e "SELECT User, Host FROM mysql.user;" 2>/dev/null)
        show_msg "Daftar MySQL" "Databases:\n$DBS\n\nUsers:\n$USERS"

        mapfile -t DB_ARRAY <<< "$DBS"
        if [[ ${#DB_ARRAY[@]} -gt 0 ]]; then
          DB_MENU=()
          for db in "${DB_ARRAY[@]}"; do
            DB_MENU+=("$db" "")
          done
          db=$(dialog --menu "Pilih Database untuk melihat tabel:" 20 60 10 "${DB_MENU[@]}" 3>&1 1>&2 2>&3) || continue
          TABLES=$(mysql -u root -p"$pass" -N -B -e "USE \`$db\`; SHOW TABLES;" 2>/dev/null)
          show_msg "Tabel MySQL" "Database: $db\nTables:\n${TABLES:-Tidak ada tabel}" 
        else
          show_msg "Error" "Gagal mengambil daftar database."
        fi
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
      7)
        service_reload "mysql"
        ;;
      8)
        service_restart "mysql"
        ;;
      0) break ;;
    esac
  done
}

# ========= FUNGSI REDIS =========
manage_redis() {
  log_action "INFO" "Managing Redis"
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen Redis" --menu "Pilih aksi:" 15 60 8 \
      1 "Info Database" \
      2 "Flush Semua Database" \
      3 "Flush Database Aktif" \
      4 "Monitor Redis" \
      5 "Reload Layanan Redis" \
      6 "Restart Layanan Redis" \
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
      5)
        service_reload "redis"
        ;;
      6)
        service_restart "redis"
        ;;
      0) break ;;
    esac
  done
}

# ========= FUNGSI POSTGRES =========
manage_postgres() {
  log_action "INFO" "Managing PostgreSQL"
  while true; do
    CHOICE=$(dialog --clear --title "Manajemen PostgreSQL" --menu "Pilih aksi:" 20 70 12 \
      1 "Daftar Database & User" \
      2 "Tambah Database" \
      3 "Hapus Database" \
      4 "Tambah User" \
      5 "Hapus User" \
      6 "Grant Privileges" \
      7 "Reload Layanan PostgreSQL" \
      8 "Restart Layanan PostgreSQL" \
      0 "Kembali" \
      3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && break

    case $CHOICE in
      1)
        pass=$(dialog --passwordbox "Password user postgres:" 10 50 3>&1 1>&2 2>&3) || continue
        DBS=$(PGPASSWORD="$pass" psql -U postgres -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null)
        USERS=$(PGPASSWORD="$pass" psql -U postgres -At -c "\\du" 2>/dev/null)
        show_msg "Daftar PostgreSQL" "Databases:\n$DBS\n\nUsers:\n$USERS"

        mapfile -t DB_ARRAY <<< "$DBS"
        if [[ ${#DB_ARRAY[@]} -gt 0 ]]; then
          DB_MENU=()
          for db in "${DB_ARRAY[@]}"; do
            DB_MENU+=("$db" "")
          done
          db=$(dialog --menu "Pilih Database untuk melihat tabel:" 20 60 10 "${DB_MENU[@]}" 3>&1 1>&2 2>&3) || continue
          TABLES=$(PGPASSWORD="$pass" psql -U postgres -d "$db" -At -c "SELECT tablename FROM pg_tables WHERE schemaname='public';" 2>/dev/null)
          show_msg "Tabel PostgreSQL" "Database: $db\nTables:\n${TABLES:-Tidak ada tabel}" 
        else
          show_msg "Error" "Gagal mengambil daftar database."
        fi
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
      7)
        service_reload "postgresql"
        ;;
      8)
        service_restart "postgresql"
        ;;
      0) break ;;
    esac
  done
}

