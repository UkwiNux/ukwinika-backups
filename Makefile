# =============================================================================
# UKwinika Backup Project Makefile
# Version: 2.3
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

# Detect OS and install required packages/dependencies automatically
deps:
	@if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
		echo "🔧 Detected Debian/Ubuntu system..."; \
		sudo apt update && sudo apt install -y borgbackup inotify-tools; \
		echo "✅ BorgBackup + inotify-tools installed (Debian)"; \
	elif [ -f /etc/redhat-release ] || [ -f /etc/os-release ] && grep -qE 'rhel|rocky|alma|centos' /etc/os-release; then \
		echo "🔧 Detected RHEL-based system (RHEL/Rocky/AlmaLinux/CentOS)..."; \
		sudo dnf install -y epel-release || true; \
		sudo dnf install -y borgbackup inotify-tools; \
		echo "✅ BorgBackup + inotify-tools installed (RHEL)"; \
	else \
		echo "ℹ️ Unknown distribution — skipping auto-install. Please install borgbackup and inotify-tools manually."; \
	fi

# Main installation target
install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@sudo mkdir -p $(PROMETHEUS_DIR)
	@echo "✅ Script Installed to $(INSTALL_DIR)/$(SCRIPT)"
	@echo "✅ v2.3 Full-featured version with Real-Time, Restore, Hooks, Prometheus, USB Detection, and Lock Handling support & RHEL Compatibility"

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
