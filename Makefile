.PHONY: install uninstall systemd clean

INSTALL_DIR=/usr/local/bin
SCRIPT=enhanced_automated_backups.sh
SYSTEMD_DIR=/etc/systemd/system
LOGROTATE_DIR=/etc/logrotate.d

install:
	@sudo install -m 700 $(SCRIPT) $(INSTALL_DIR)/
	@echo "✅ Script installed to $(INSTALL_DIR)/$(SCRIPT)"

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
