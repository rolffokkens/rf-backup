DESTDIR = /tmp/rf-backup

all:

install:
	install -d $(DESTDIR)/usr/lib/udev/rules.d/ $(DESTDIR)/usr/lib/systemd/system \
	$(DESTDIR)/usr/share/rf-backup $(DESTDIR)/etc/rf-backup.d/
	install -m 644 99-rf-backups.rules $(DESTDIR)/usr/lib/udev/rules.d/99-rf-backups.rules
	install -m 755 checklabel.sh $(DESTDIR)/usr/share/rf-backup
	install -m 755 do-backup.sh $(DESTDIR)/usr/share/rf-backup
	install -m 755 rf-backup.lib.sh $(DESTDIR)/usr/share/rf-backup/rf-backup.lib.sh
	install -m 644 rf-backup@.service $(DESTDIR)/usr/lib/systemd/system/rf-backup@.service
	install -m 644 sample.conf $(DESTDIR)/etc/rf-backup.d/sample.conf.sample
	install -m 644 sample.exclude $(DESTDIR)/etc/rf-backup.d/sample.exclude.sample
