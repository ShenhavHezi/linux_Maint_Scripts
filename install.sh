#!/usr/bin/env bash
# install.sh - Installer for Linux_Maint_Scripts (recommended Linux paths)
#
# Installs:
# - wrapper: /usr/local/sbin/run_full_health_monitor.sh
# - library: /usr/local/lib/linux_maint.sh
# - monitors: /usr/local/libexec/linux_maint/*.sh (explicit list)
#
# Optional:
# - create linuxmaint user
# - create systemd service/timer
# - install logrotate config
#
# Usage examples:
#   sudo ./install.sh
#   sudo ./install.sh --with-user --with-timer --with-logrotate
#   sudo ./install.sh --uninstall

set -euo pipefail

WITH_USER=false
WITH_TIMER=false
WITH_LOGROTATE=false
UNINSTALL=false
PURGE=false
USER_NAME="linuxmaint"
INSTALL_PREFIX="/usr/local"

usage(){
  cat <<EOF
Usage: sudo $0 [options]

Options:
  --with-user            Create dedicated user (${USER_NAME}) if missing
  --with-timer           Install and enable systemd service+timer (daily)
  --with-logrotate       Install /etc/logrotate.d/linux_maint
  --user NAME            Set username (default: ${USER_NAME})
  --prefix PATH          Install prefix (default: ${INSTALL_PREFIX})
  --uninstall            Remove installed files (keeps /etc/linux_maint and logs)
  --purge                With --uninstall: also remove systemd units + logrotate + optional dirs
  -h, --help             Show help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-user) WITH_USER=true; shift;;
    --with-timer) WITH_TIMER=true; shift;;
    --with-logrotate) WITH_LOGROTATE=true; shift;;
    --uninstall) UNINSTALL=true; shift;;
    --purge) PURGE=true; shift;;
    --user) USER_NAME="$2"; shift 2;;
    --prefix) INSTALL_PREFIX="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 2;;
  esac
done

need_root(){
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: must run as root" >&2
    exit 1
  fi
}

create_user(){
  local u="$1"
  if id "$u" >/dev/null 2>&1; then
    echo "User $u already exists"
    return 0
  fi
  echo "Creating user $u"
  useradd -r -m -s /bin/bash "$u"
}

install_files(){
  local prefix="$1"
  local sbin="$prefix/sbin"
  local lib="$prefix/lib"
  local libexec="$prefix/libexec/linux_maint"

  echo "Installing to:"
  echo "  wrapper:  $sbin/run_full_health_monitor.sh"
  echo "  library:  $lib/linux_maint.sh"
  echo "  monitors: $libexec/"

  install -D -m 0755 linux_maint.sh "$lib/linux_maint.sh"
  install -D -m 0755 run_full_health_monitor.sh "$sbin/run_full_health_monitor.sh"
  install -d "$libexec"

  # Explicit monitors list (exclude wrapper + lib)
  install -D -m 0755 \
    backup_check.sh cert_monitor.sh config_drift_monitor.sh health_monitor.sh \
    inode_monitor.sh inventory_export.sh network_monitor.sh nfs_mount_monitor.sh \
    ntp_drift_monitor.sh patch_monitor.sh storage_health_monitor.sh kernel_events_monitor.sh \
    preflight_check.sh disk_trend_monitor.sh \
    ports_baseline_monitor.sh service_monitor.sh user_monitor.sh \
    "$libexec/"

  # Hardening
  chown -R root:root "$libexec"
  chmod -R go-w "$libexec"

  # Directories
  mkdir -p /etc/linux_maint /etc/linux_maint/baselines /var/log/health /var/lib/linux_maint

  # Build/version info (optional; present in offline release tarballs)
  mkdir -p "$prefix/share/linux_maint"
  if [ -f "BUILD_INFO" ]; then
    install -m 0644 BUILD_INFO "$prefix/share/linux_maint/BUILD_INFO"
  fi

  echo "Install complete. Try: $sbin/run_full_health_monitor.sh"
}

install_logrotate(){
  echo "Installing logrotate config to /etc/logrotate.d/linux_maint"
  cat > /etc/logrotate.d/linux_maint <<'EOF'
/var/log/*monitor*.log /var/log/*_monitor.log /var/log/*_check.log /var/log/inventory_export.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}

/var/log/health/*.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
EOF
}

install_systemd(){
  echo "Installing systemd unit + timer"

  cat > /etc/systemd/system/linux-maint.service <<EOF
[Unit]
Description=Linux maintenance full health monitor

[Service]
Type=oneshot
ExecStart=${INSTALL_PREFIX}/sbin/run_full_health_monitor.sh
EOF

  cat > /etc/systemd/system/linux-maint.timer <<'EOF'
[Unit]
Description=Run Linux maintenance health checks daily

[Timer]
OnCalendar=*-*-* 02:15:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now linux-maint.timer
  systemctl status linux-maint.timer --no-pager || true
}

uninstall_files(){
  local prefix="$1"
  echo "Uninstalling from prefix: $prefix"
  rm -f "$prefix/sbin/run_full_health_monitor.sh"
  rm -f "$prefix/lib/linux_maint.sh"
  rm -rf "$prefix/libexec/linux_maint"
  echo "Uninstall complete. (Kept /etc/linux_maint and /var/log by default.)"
  if $PURGE; then
    echo "Purging systemd units and logrotate (and optional dirs)"
    rm -f /etc/systemd/system/linux-maint.service /etc/systemd/system/linux-maint.timer
    systemctl daemon-reload >/dev/null 2>&1 || true
    rm -f /etc/logrotate.d/linux_maint
    rm -rf /var/log/health || true
    # Uncomment if you want to also remove config/baselines:
    # rm -rf /etc/linux_maint
  fi
}

need_root

if $UNINSTALL; then
  uninstall_files "$INSTALL_PREFIX"
  exit 0
fi

$WITH_USER && create_user "$USER_NAME"
install_files "$INSTALL_PREFIX"
$WITH_LOGROTATE && install_logrotate
$WITH_TIMER && install_systemd

exit 0
