#!/usr/bin/env bash
# shellcheck disable=SC2207
#
# Shellcheck ignore list:
#  - SC2207: Prefer mapfile or read -a to split command output (or quote to avoid splitting).
#  Rationale: Required for compgen idiomatic use
#
# (C) Copyright 2018, 2019 Diomidis Spinellis
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
# Arguments: the current word
_gi_autocomplete_subcommand()
{
  local IFS=$'\n' command_regex='^\s{3}([a-z]+)\s.*'

  # parse help information for sub commands
  while read -r line; do
    # match only the command lines a.k.a. "gi <subcommand>: command help"
    if [[ $line =~ $command_regex ]]; then
      COMPREPLY+=($(compgen -W "${BASH_REMATCH[1]}" -- "$1"))
    fi
  done <<< "$(git issue help 2>/dev/null)"
}

# Autocompletes the gi subcommands' argument sequence.
# Arguments: the subcommand, the current word
_gi_autocomplete_subcommand_argument()
{
  case $1 in
    show | comment | tag | assign | attach | watcher | weight | create)
      # list all issues
      list_args="-a"
      ;;
    edit | close | milestone | duedate | timeestimate | timespent)
      # list only open issues
      list_args=""
      ;;
    *)
      # stop completion for the rest of the sub-commands
      return
  esac

  local IFS=$'\n' desc sha cmd gi_list

  while read -r line; do
    # shellcheck disable=SC2001
    # SC2001: See if you can use ${variable//search/replace} instead.
    # Rationale: Can't, because it doesn't handle \n
    desc=($(echo "$line" | sed 's/ /\n/'))
    cmd=$(compgen -W "${desc[0]}" -- "$2")

    if [ -n "$cmd" ]; then
      # Store the matching issues along with their description
      gi_list+=($(printf '%*s' "-$COLUMNS" "$cmd - ${desc[1]}"))
    fi
  done <<< "$(git issue list $list_args 2>/dev/null)"

  if [[ ${#gi_list[@]} == 1 ]]; then
    # If only one match, autocomplete the sha without the description
    sha="${gi_list[0]/%\ */}"
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
        _gi_autocomplete_subcommand "$word"
    else
        local subcmd="${COMP_WORDS[$baseidx]}"
        local prev_word="${COMP_WORDS[COMP_CWORD-1]}"
        # completion is only implemented directly after a subcommand or after a
        # subcommand's flag, that is at maximum two positions further
        local max_pos=$(( "$baseidx" + "2" ))

        # stop completion if we already passed the hash argument
        [ "$COMP_CWORD" -gt "$max_pos" ] && return
        [ "$COMP_CWORD" -eq "$max_pos" ] && [[ $prev_word != -* ]] && return

        _gi_autocomplete_subcommand_argument "$subcmd" "$word"
    fi 
  else
    __git_wrap__gitk_main
  fi
}

_git_issue() {
  _gi_autocomplete
}

complete -F _gi_autocomplete gi
