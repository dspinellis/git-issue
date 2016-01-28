#!/bin/sh
#
# (C) Copyright 2016 Diomidis Spinellis
#
# This file is part of gi, the Git-based issue management system.
#
# gi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# gi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with CScout.  If not, see <http://www.gnu.org/licenses/>.
#

# Display system usage and exit
usage()
{
  cat <<\USAGE_EOF
usage: gi <command> [<args>]
The following commands are available
gi init: Verifies system functionality
gi new: Creates a new issue and marks it as open.
gi list: Lists the issues with the specified tag.
gi show: Shows specified issue.
gi comment: Adds an issue comment.
gi tag: Adds (or removes with -r) a tag.
gi assign: Assigns (or reassigns) an issue to a person.
gi attach: Attaches (or removes with -r) a file to an issue.
gi watch: Adds (or removes with -r) an issue watcher.
gi close: Removes the open tag from the issue, marking it as closed.
gi push: Update remote repository with local changes.
gi pull: Update local repository with remote changes.
gi git: Run the specified Git command on the issues repository.
USAGE_EOF
  exit 1
}
