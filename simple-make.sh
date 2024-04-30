#!/bin/sh
#
# Convert the Makefile into a shell script and # execute it via the shell
#

sed -n '
  # Set optional variables
  / ?= / {
    s/[()"]//g
    s/\([^ ]*\) ?= \(.*\)/\1="${\1:-\2}"/
    p
    b
  }

  # Convert Makefile rules into shell functions
  /:$/ {
    s/^\([^\t].*\):$/\1() {/p
    n
    :body
    s/^\t@/\t/
    y/()/{}/
    s/^\t/  /p
    # Close function and terminate block processing on empty line
    # (Reset "t" status)
    t reset
    :reset
    s/^$/}/p
    t
    # Read next line and repeat
    n
    b body
  }

  # Convert the PHONY rules list into a case statement
  /^\.PHONY:/ {
    s/^\.PHONY: default //
    i\
case "'$1'" in
    s/ /|/g
    s/$/)/p
    i\
      '$1'\
      ;;\
    *)
      s/^/      echo "Usage: gfw_make {/
      s/)$/}"/p
    i\
      ;;\
esac
}
' Makefile | bash
