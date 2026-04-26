# =============================================================================
# UKwinika Backup Project Makefile – (idempotent edition)
# Author: Urayayi Kwinika
# Description: Handles Installation, Dependencies, and Systemd Deployment
# Supports Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS Systems
# =============================================================================

.PHONY: install uninstall systemd clean deps

INSTALL_DIR=/usr/local/bin
SCRIPT=enhanced_automated_backups.sh
SYSTEMD_DIR=/etc/systemd/system
LOGROTATE_DIR=/etc/logrotate.d
PROMETHEUS_DIR=/var/lib/prometheus/node_exporter/custom

deps:
	@if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
		echo "🔧 Detected Debian/Ubuntu System..."; \
		sudo apt update && sudo apt install -y borgbackup inotify-tools; \
	elif [ -f /etc/redhat-release ] || [ -f /etc/os-release ] && grep -qE 'rhel|rocky|alma|centos' /etc/os-release; then \
		echo "🔧 Detected RHEL-based System (RHEL/Rocky/AlmaLinux/CentOS)..."; \
		sudo dnf install -y epel-release || true; \
		sudo dnf install -y borgbackup inotify-tools; \
	else \
		echo "ℹ️ Unknown Distribution — please install Borgbackup and inotify-tools manually."; \
	fi

install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@sudo mkdir -p $(PROMETHEUS_DIR)
	@echo "✅ Script Installed to $(INSTALL_DIR)/$(SCRIPT)"
	@echo "✅ Smart Idempotent Edition with full 3‑2‑1 Backup Stragety Implementation, Safe Restore, and Lock Cleanup."

uninstall: 
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT)
	@echo "✅ Script Removed"

systemd: 
	@sudo cp systemd/* $(SYSTEMD_DIR)/
	@sudo cp logrotate/ukwinika-backup $(LOGROTATE_DIR)/
	@sudo systemctl daemon-reload
	@echo "✅ Systemd Services and Logrotate Installed"

clean: 
	@sudo rm -f /var/log/UKwinikaBackup*.log
	@echo "✅ Logs Cleaned"
