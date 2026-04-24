# =============================================================================
# UKwinika Backup Project Makefile – (idempotent edition)
# Version: v3.0
# Author: Urayayi Kwinika
# Description: Handles installation, dependencies, and systemd deployment
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
		echo "🔧 Detected Debian/Ubuntu system..."; \
		sudo apt update && sudo apt install -y borgbackup inotify-tools; \
	elif [ -f /etc/redhat-release ] || [ -f /etc/os-release ] && grep -qE 'rhel|rocky|alma|centos' /etc/os-release; then \
		echo "🔧 Detected RHEL-based system (RHEL/Rocky/AlmaLinux/CentOS)..."; \
		sudo dnf install -y epel-release || true; \
		sudo dnf install -y borgbackup inotify-tools; \
	else \
		echo "ℹ️ Unknown distribution — please install borgbackup and inotify-tools manually."; \
	fi

install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@sudo mkdir -p $(PROMETHEUS_DIR)
	@echo "✅ Script installed to $(INSTALL_DIR)/$(SCRIPT)"
	@echo "✅ v3.0 – Smart idempotent edition with full 3‑2‑1, safe restore, and lock cleanup."

uninstall: 
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT)
	@echo "✅ Script removed"

systemd: 
	@sudo cp systemd/* $(SYSTEMD_DIR)/
	@sudo cp logrotate/ukwinika-backup $(LOGROTATE_DIR)/
	@sudo systemctl daemon-reload
	@echo "✅ Systemd services and logrotate installed"

clean: 
	@sudo rm -f /var/log/UKwinikaBackup*.log
	@echo "✅ Logs cleaned"
