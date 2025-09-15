#!/bin/bash

DEVPANEL_DIR="$HOME/.devpanel"
SITEDB="$DEVPANEL_DIR/sites"
LOGFILE="$DEVPANEL_DIR/panel-data.log"
DNSMASQ_DEV_CONF="/etc/dnsmasq.d/devpanel.conf"

mkdir -p "$SITEDB"

hash_id() { echo -n "$1" | md5sum | awk '{print $1}'; }

# Log an action to the logfile
#
# Parameters:
#   $1 - The log level (e.g. "INFO", "ERROR")
#   $2 - The log message
#
# Log format:
#   [YYYY-MM-DD HH:MM:SS] [LEVEL] MESSAGE
log_action() {
  local level="$1"
  local message="$2"
  printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" >> "$LOGFILE"
}

# Show a message to the user and log the action
#
# Parameters:
#   $1 - The title of the message box
#   $2 - The message to display
#
# Returns:
#   None
show_msg() {
  dialog --title "$1" --msgbox "$2" 20 70
  log_action "INFO" "$1 - $2"
}

# Check if all dependencies are installed
#
# If any dependencies are missing, print error message
# and exit with code 1
#
# Parameters: None
#
# Returns: None
check_dependencies() {
  log_action "INFO" "Checking dependencies"
  missing_deps=()

  command -v dialog >/dev/null || missing_deps+=("dialog")
  command -v nginx >/dev/null || missing_deps+=("nginx")

  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_action "ERROR" "Missing dependencies: ${missing_deps[*]}"
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

# Exit the DevPanel program
#
# This function will clear the screen, display a goodbye message, and exit the program with code 0.
#
# Parameters:
#   None
#
# Returns:
#   None
exit_panel() {
  clear
  echo "[DevPanel] Berhasil memberhentikan layanan."
  echo "[DevPanel] Sampai jumpa kembali dilain waktu!"
  exit 0
}

