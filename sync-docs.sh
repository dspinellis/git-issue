#!/bin/sh
#
# (C) Copyright 2016-2018 Diomidis Spinellis
#
# This file is part of git-issue, the Git-based issue management system.
#
# git-issue is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# git-issue is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with git-issue.  If not, see <http://www.gnu.org/licenses/>.
#

# Synchronize script and its documentation with the contents of the README file

SCRIPT_NAME=git-issue.sh
MAN_PAGE=git-issue.1

# Update usage information in the script based on README.md
{
  sed -n '1,/^The following commands are available/p' $SCRIPT_NAME
  sed -n '/^\* `git issue init`/,/^\* `git issue git`/ {
    /^\* /!d
    s/`//g
    s/^\* //
    p
  }' README.md
  sed -n '/^USAGE_EOF/,$p' $SCRIPT_NAME
} >newgi.sh
mv newgi.sh $SCRIPT_NAME
chmod +x git-issue.sh

# Update the specified man section from the specified README section
# pre-processing its body with the given sed command
replace_section()
{
  local man_section="$1"
  local md_section="$2"
  local command="$3"

  {
    # Output until the specified section
    sed -n "1,/^\\.SH $man_section/p" $MAN_PAGE

    # Output specified section from README
    echo '.\" Auto-generated content from README.md; do not edit this section'
    sed -n "/^## $md_section/,/^## / {
      $command"'
      # Remove section titles
      /^## /d
      # Set code text with Courier (twice per line)
      s/`/\\fC/;s/`/\\fP/
      s/`/\\fC/;s/`/\\fP/
      # Set italic text (twice per line)
      s/_/\\fI/;s/_/\\fP/
      s/_/\\fI/;s/_/\\fP/
      # Set first-level and second-level bullets
      s/^\* /.IP "" 4\n/
      s/^  \* /.IP "" 8\n/
      s/^    \* /.IP "" 12\n/
      s/\[\([^]]*\)\](\([^)]*\))/\1 <\2>/
      p
    }' README.md

    # Output the rest of the man page
    sed -n "1,/^\\.SH $man_section/d;{/^\\.SH /,/xyzzy/p}" $MAN_PAGE
  } >man-$$.1
  mv man-$$.1 $MAN_PAGE
}

# Update subcommands, implementation, and examples in the manual page
# from the README file
replace_section 'GIT ISSUE COMMANDS' 'Use' 's/^\* `\([^`]*\)`: /.RE\n.PP\n\\fB\1\\fP\n.RS 4\n/'
replace_section FILES 'Internals'
replace_section EXAMPLES 'Example session' 's/^\$ # \(.*\)/.ft P\n.fi\n.PP\n\1\n.ft C\n.nf/;s/^\$ \(...*\) # \(.*\)/.ft P\n.fi\n.PP\n\2\n.ft C\n.nf\n\1/;s/```/.ft P\n.fi/'
