### 2. Updated Makefile  

.PHONY: install uninstall systemd clean deps

INSTALL_DIR=/usr/local/bin
SCRIPT=enhanced_automated_backups.sh
SYSTEMD_DIR=/etc/systemd/system
LOGROTATE_DIR=/etc/logrotate.d

# Automatic dependency installation (Borg on Debian/Ubuntu)
deps:
	@if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then \
		if ! command -v borg >/dev/null 2>&1; then \
			echo "🔧 Installing BorgBackup automatically for Debian/Ubuntu..."; \
			sudo apt update && sudo apt install -y borgbackup; \
			echo "✅ BorgBackup installed"; \
		else \
			echo "✅ BorgBackup already installed"; \
		fi; \
	else \
		echo "ℹ️  Non-Debian system detected — skipping automatic Borg install"; \
	fi

install: deps
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@sudo sed -i 's/--encryption=repokey-aes256/--encryption=repokey/g' $(INSTALL_DIR)/$(SCRIPT) || true
	@echo "✅ Script installed to $(INSTALL_DIR)/$(SCRIPT)"
	@echo "✅ Borg encryption flag auto-patched for Debian/Borg 1.4 compatibility"

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
