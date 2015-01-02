DESTDIR = /tmp/rf-backup

all:

install: install-common install-rules

install-f20: install-common install-rules-f20

install-common:
	install -d $(DESTDIR)/usr/lib/udev/rules.d/ $(DESTDIR)/usr/lib/systemd/system \
	$(DESTDIR)/usr/share/rf-backup/locale $(DESTDIR)/etc/rf-backup.d/ \
	 $(DESTDIR)/var/run/rf-backup $(DESTDIR)/usr/lib/tmpfiles.d/
	install -m 755 checklabel.sh $(DESTDIR)/usr/share/rf-backup/checklabel.sh
	install -m 755 mark-remove.sh $(DESTDIR)/usr/share/rf-backup/mark-remove.sh
	install -m 755 do-backup.sh $(DESTDIR)/usr/share/rf-backup/do-backup.sh
	install -m 755 rf-backup.lib.sh $(DESTDIR)/usr/share/rf-backup/rf-backup.lib.sh
	install -m 644 rf-backup@.service $(DESTDIR)/usr/lib/systemd/system/rf-backup@.service
	install -m 644 sample.conf $(DESTDIR)/etc/rf-backup.d/sample.conf.sample
	install -m 644 sample.exclude $(DESTDIR)/etc/rf-backup.d/sample.exclude.sample
	install -m 644 locale/* $(DESTDIR)/usr/share/rf-backup/locale
	install -m 644 tmpfiles.conf $(DESTDIR)/usr/lib/tmpfiles.d/rf-backup.conf

install-rules:
	install -m 644 99-rf-backups.rules $(DESTDIR)/usr/lib/udev/rules.d/99-rf-backups.rules

install-rules-f20:
	install -m 644 99-rf-backups.rules.f20 $(DESTDIR)/usr/lib/udev/rules.d/99-rf-backups.rules
