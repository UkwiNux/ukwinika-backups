# =============================================================================
# UKwinika Backup Project Makefile – v3.2 (Idempotent Edition)
# Author: Urayayi Kwinika
# Description: Handles installation, dependencies, and systemd deployment.
# Supports Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS systems.
# =============================================================================

.PHONY: install uninstall systemd clean deps

INSTALL_DIR   = /usr/local/bin
SCRIPT        = enhanced_automated_backups.sh
RESTORE_SCRIPT = ukwinika_automated_restore.sh
SYSTEMD_DIR   = /etc/systemd/system
LOGROTATE_DIR = /etc/logrotate.d

# ---------------------------------------------------------------------------
# deps – install all runtime dependencies
# ---------------------------------------------------------------------------
deps:
	@if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
		echo "🔧 Detected Debian/Ubuntu system..."; \
		sudo apt-get update && sudo apt-get install -y \
			borgbackup \
			inotify-tools \
			rsync \
			mailutils; \
	elif [ -f /etc/redhat-release ] || \
	     ([ -f /etc/os-release ] && grep -qE 'rhel|rocky|alma|centos' /etc/os-release); then \
		echo "🔧 Detected RHEL-based system (RHEL/Rocky/AlmaLinux/CentOS)..."; \
		sudo dnf install -y epel-release || true; \
		sudo dnf install -y \
			borgbackup \
			inotify-tools \
			rsync \
			mailx; \
	else \
		echo "ℹ️  Unknown distribution — please install borgbackup, inotify-tools, rsync, and a mail client manually."; \
	fi

# ---------------------------------------------------------------------------
# install – copy both scripts and set permissions (depends on deps)
# ---------------------------------------------------------------------------
install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@echo "✅ Backup script installed to $(INSTALL_DIR)/$(SCRIPT)"
	@sudo install -m 700 $(RESTORE_SCRIPT) $(INSTALL_DIR)/
	@echo "✅ Restore script installed to $(INSTALL_DIR)/$(RESTORE_SCRIPT)"
	@echo "✅ Smart idempotent edition with full 3-2-1 backup strategy, safe restore, and lock cleanup."

# ---------------------------------------------------------------------------
# uninstall – remove both installed scripts
# ---------------------------------------------------------------------------
uninstall:
	@sudo rm -f $(INSTALL_DIR)/$(SCRIPT)
	@echo "✅ Backup script removed from $(INSTALL_DIR)"
	@sudo rm -f $(INSTALL_DIR)/$(RESTORE_SCRIPT)
	@echo "✅ Restore script removed from $(INSTALL_DIR)"

# ---------------------------------------------------------------------------
# systemd – deploy all service units and logrotate configuration
# ---------------------------------------------------------------------------
systemd:
	@sudo cp systemd/* $(SYSTEMD_DIR)/
	@sudo cp logrotate/ukwinika-backup $(LOGROTATE_DIR)/
	@sudo systemctl daemon-reload
	@echo "✅ Systemd services and logrotate installed"
	@echo ""
	@echo "   Backup — enable the daily timer:"
	@echo "     sudo systemctl enable --now ukwinika-backup.timer"
	@echo ""
	@echo "   Backup — enable real-time monitoring (optional):"
	@echo "     sudo systemctl enable --now ukwinika-realtime-backup.service"
	@echo ""
	@echo "   Restore drill — enable the monthly timer:"
	@echo "     sudo systemctl enable --now ukwinika-restore-test.timer"

# ---------------------------------------------------------------------------
# clean – remove runtime logs and restore drill directories
# ---------------------------------------------------------------------------
clean:
	@sudo rm -f /var/log/UKwinikaBackup*.log
	@sudo rm -f /var/log/UKwinikaRestore*.log
	@echo "✅ Logs cleaned"
	@sudo $(INSTALL_DIR)/$(RESTORE_SCRIPT) clean 2>/dev/null || true
	@echo "✅ Restore drill directories cleaned"
