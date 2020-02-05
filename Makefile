prefix      := /usr/local
exec_prefix := $(prefix)
bindir      := $(exec_prefix)/bin
libexecdir  := $(exec_prefix)/libexec
sysconfdir  := $(prefix)/etc
datarootdir := $(prefix)/share
mandir      := $(datarootdir)/man
man1dir     := $(mandir)/man1

default: install

install:
	mkdir -p "$(bindir)" "$(libexecdir)/git-issue" "$(sysconfdir)/bash_completion.d" "$(man1dir)"
	install git-issue.sh $(bindir)/git-issue
	install lib/git-issue/import-export.sh $(libexecdir)/git-issue/import-export.sh
	install -m 644 git-issue.1 $(man1dir)/
	install -m 644 gi-completion.sh $(sysconfdir)/bash_completion.d/git-issue

# Synchronize man page and usage with the contents of the README file
sync-docs:
	./sync-docs.sh

test:
	if shellcheck --version >/dev/null 2>&1 ; then \
	  shellcheck -x *.sh lib/git-issue/*.sh ; \
	else \
	  echo 'Skipping shellcheck; consider installing it' ; \
	fi
	./test.sh

uninstall:
	rm -f $(bindir)/git-issue
	rm -f $(man1dir)/git-issue.
	rm -f $(sysconfdir)/bash_completion.d/git-issue

clean:

.PHONY: default clean install uninstall sync-docs test
