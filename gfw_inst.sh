#!/bin/bash

# Set default values if not already set
PREFIX="${PREFIX:-/usr/local}"
BINPREFIX="${BINPREFIX:-$PREFIX/bin}"
LIBPREFIX="${LIBPREFIX:-$PREFIX/lib}"
MANPREFIX="${MANPREFIX:-$PREFIX/share/man/man1}"
SYSCONFDIR="${SYSCONFDIR:-$PREFIX/etc}"

# Function to install
install_stuff() {
    mkdir -p "${DESTDIR}${MANPREFIX}"
    mkdir -p "${DESTDIR}${BINPREFIX}"
    mkdir -p "${DESTDIR}${LIBPREFIX}/git-issue"
    sed "s|/usr/local|${PREFIX}|g" git-issue.sh > git-issue
    install git-issue "${DESTDIR}${BINPREFIX}/git-issue"
    install lib/git-issue/import-export.sh "${DESTDIR}${LIBPREFIX}/git-issue/import-export.sh"
    install -m 644 git-issue.1 "${DESTDIR}${MANPREFIX}/"
    mkdir -p "${DESTDIR}${SYSCONFDIR}/bash_completion.d"
    install -m 644 gi-completion.sh "${DESTDIR}${SYSCONFDIR}/bash_completion.d/git-issue"
}
 
# Function to synchronize documentation
sync-docs() {
    ./sync-docs.sh
}
 
# Function to run tests
runtests() {
    if shellcheck --version >/dev/null 2>&1 ; then
        shellcheck -x *.sh lib/git-issue/*.sh
    else
        echo 'Skipping shellcheck; consider installing it'
    fi
    ./test.sh
}
 
# Function to uninstall
uninstall() {
    rm -f "${DESTDIR}${BINPREFIX}/git-issue"
    rm -f "${DESTDIR}${MANPREFIX}/git-issue."
    rm -f "${DESTDIR}${SYSCONFDIR}/bash_completion.d/git-issue"
}
 
# Function to clean up files
clean() {
    rm -f git-issue
}
 
# Main function to handle script calling logic
main() {
    case "$1" in
        install)
            install_stuff
            ;;
        sync-docs)
            sync-docs
            ;;
        test)
            runtests
            ;;
        uninstall)
            uninstall
            ;;
        clean)
            clean
            ;;
        *)
            echo "Usage: $0 {install|sync-docs|test|uninstall|clean}"
            exit 1
            ;;
    esac
}
 
# Call main with all the arguments
main "$@"
