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
USAGE_EOF
  exit 1
}
