# =============================================================================
# UKwinika Backup Project Makefile
# Version: 2.3
# Author: Urayayi Kwinika
# Description: Handles installation, dependencies, and systemd deployment
# Changes in v2.3: Added Prometheus directory creation + full feature notice
# =============================================================================

.PHONY: install uninstall systemd clean deps

INSTALL_DIR=/usr/local/bin
SCRIPT=enhanced_automated_backups.sh
SYSTEMD_DIR=/etc/systemd/system
LOGROTATE_DIR=/etc/logrotate.d
PROMETHEUS_DIR=/var/lib/prometheus/node_exporter/custom

# Install required packages automatically on Debian/Ubuntu
deps:
	@if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
		echo "🔧 Installing dependencies for Debian/Ubuntu..."; \
		sudo apt update && sudo apt install -y borgbackup inotify-tools; \
		echo "✅ BorgBackup + inotify-tools installed"; \
	else \
		echo "ℹ️ Non-Debian system — skipping auto-install"; \
	fi

# Main installation target
install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@sudo mkdir -p $(PROMETHEUS_DIR)
	@echo "✅ Script installed to $(INSTALL_DIR)/$(SCRIPT)"
	@echo "✅ v2.3 full-featured version with real-time, restore, hooks, Prometheus, USB detection, and lock handling"

# Remove the script
uninstall: 
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT)
	@echo "✅ Script Removed"

# Deploy systemd services and logrotate
systemd: 
	@sudo cp systemd/* $(SYSTEMD_DIR)/
	@sudo cp logrotate/ukwinika-backup $(LOGROTATE_DIR)/
	@sudo systemctl daemon-reload
	@echo "✅ Systemd Services and Logrotate Installed"

# Clean old log files
clean: 
	@sudo rm -f /var/log/UKwinikaBackup*.log
	@echo "✅ Logs Cleaned"
