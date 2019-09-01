PREFIX ?= /usr/local
BINPREFIX ?= "$(PREFIX)/bin"
LIBPREFIX ?= "$(PREFIX)/lib"
MANPREFIX ?= "$(PREFIX)/share/man/man1"
SYSCONFDIR ?= $(PREFIX)/etc

default: install

install:
	@mkdir -p $(DESTDIR)$(MANPREFIX)
	@mkdir -p $(DESTDIR)$(BINPREFIX)
	@mkdir -p $(DESTDIR)$(LIBPREFIX)/git-issue
	install git-issue.sh $(DESTDIR)$(BINPREFIX)/git-issue
	install lib/git-issue/import-export.sh $(DESTDIR)$(LIBPREFIX)/git-issue/import-export.sh
	install -m 644 git-issue.1 $(DESTDIR)$(MANPREFIX)/
	@mkdir -p $(DESTDIR)$(SYSCONFDIR)/bash_completion.d
	install -m 644 gi-completion.sh $(DESTDIR)$(SYSCONFDIR)/bash_completion.d/git-issue

# Synchronize man page and usage with the contents of the README file
sync-docs:
	./sync-docs.sh

test:
	shellcheck --version >/dev/null 2>&1 && \
		shellcheck -x *.sh lib/git-issue/*.sh || \
		echo 'Skipping shellcheck; consider installing it'
	./test.sh

uninstall:
	rm -f $(DESTDIR)$(BINPREFIX)/git-issue
	rm -f $(DESTDIR)$(MANPREFIX)/git-issue.
	rm -f $(DESTDIR)$(SYSCONFDIR)/bash_completion.d/git-issue

clean:

.PHONY: default clean install uninstall sync-docs test
