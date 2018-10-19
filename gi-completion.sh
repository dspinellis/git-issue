#!/bin/sh
#
# (C) Copyright 2018 Diomidis Spinellis
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
# along with gi.  If not, see <http://www.gnu.org/licenses/>.
#

# Autocompletes the gi subcommand sequence.
_gi_autocomplete_subcommand()
{
  local IFS=$'\n' command_regex="git issue\s([^:]*):.*"

  # parse help information for sub commands
  while read -r line; do
    # match only the command lines a.k.a. "gi <subcommand>: command help"
    if [[ $line =~ $command_regex ]]; then
      COMPREPLY+=($(compgen -W "${BASH_REMATCH[1]}" -- "$1"))
    fi
  done <<< "$(git issue help 2>/dev/null)"
}

# Autocompletes the gi subcommands' argument sequence.
_gi_autocomplete_subcommand_argument()
{
  local list_args subcommand=${COMP_WORDS[COMP_CWORD-1]}

  case $subcommand in
    show | comment | tag | assign | attach | watcher)
      # list all issues
      list_args="-a"
      ;;
    edit | close | milestone)
      # list only open issues
      list_args=""
      ;;
    *)
      # stop completion for the rest of the sub-commands
      return
  esac

  local IFS=$'\n' desc sha cmd gi_list

  while read -r line; do
    desc=($(echo $line | sed 's/ /\n/'))
    cmd=$(compgen -W "${desc[0]}" -- "$1")

    if [ -n "$cmd" ]; then
      # Store the matching issues along with their description
      gi_list+=($(printf '%*s' "-$COLUMNS" "$cmd - ${desc[1]}"))
    fi
  done <<< "$(git issue list $list_args 2>/dev/null)"

  if [[ ${#gi_list[@]} == 1 ]]; then
    # If only one match, autocomplete the sha without the description
    sha=$(echo ${gi_list[0]/%\ */})
    COMPREPLY+=($(compgen -W "$sha"))
  else
    # Display the whole sha list along with the descriptions
    COMPREPLY+=("${gi_list[@]}")
  fi
}

# Handles auto-completion of the gi executable.
_gi_autocomplete()
{
  local word="${COMP_WORDS[COMP_CWORD]}"
  local basecmd=${COMP_WORDS[0]}
  local baseidx="-1"
  if [ "$basecmd" = "gi" ]; then
    baseidx="1"
  else
    basecmd="${COMP_WORDS[1]}"
    if [ "$basecmd" = "issue" ]; then
      baseidx="2"
    else
      baseidx="-1"
    fi
  fi

  if [ "$COMP_CWORD" -ge "$baseidx" ]; then
    if [ "$COMP_CWORD" -eq "$baseidx" ]; then
        _gi_autocomplete_subcommand $word
    else
        _gi_autocomplete_subcommand_argument $word
    fi 
  else
    __git_wrap__gitk_main
  fi
}

function _git_issue() {
  _gi_autocomplete
}

complete -F _gi_autocomplete gi
