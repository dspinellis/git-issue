#!/bin/sh
#
# Check which commands are missing from the script
#

# Get all available sub-commands
git issue help |
  # Convert to complete command
  sed -n 's/^   \([^ ]*\).*/git issue \1/p' |
  while read cmd ; do
    if ! grep -q "^\\$ $cmd" youtube-script.sh ; then
      echo $cmd needs example
    fi
  done
