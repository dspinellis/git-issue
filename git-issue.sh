#!/bin/sh
# shellcheck disable=SC2039,SC1117
#
# Shellcheck ignore list:
#  - SC2039: In POSIX sh, 'local' is undefined.
#    Rationale: Local makes for better code and works on many modern shells
#  - SC1117: Backslash is literal. Prefer explicit escaping.
#
# (C) Copyright 2016-2019 Diomidis Spinellis
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

# User agent string
# shellcheck disable=SC2034
# SC2034 : USER_AGENT appears unused. Verify use (or export if used externally)
USER_AGENT=https://github.com/dspinellis/git-issue/tree/b7e1353

# Determine our script library path
my_IFS=$IFS
IFS=:

# shellcheck disable=SC2086
# Rationale: Word splitting not an issue
LD_LIBRARY_PATH="$(dirname $0)/lib:$LD_LIBRARY_PATH:/usr/lib:/usr/local/lib"
for i in ${LD_LIBRARY_PATH} ; do
  if [ -d "${i}/git-issue" ] ; then
    MY_LIB="${i}/git-issue"
    break
  fi
done

IFS=$my_IFS

if command -v gdate > /dev/null ; then
  DATEBIN="gdate"
else
  DATEBIN="date"
fi

# Exit after displaying the specified error
error()
{
  echo "$1" 1>&2
  exit 1
}

$DATEBIN --help | grep 'gnu' > /dev/null || error "Require GNU date"
# Return a unique identifier for the specified file
filesysid()
{
  stat --printf='%d:%i' "$1" 2>/dev/null ||
    stat -f '%d:%i' "$1"
}

# Move to the .issues directory
cdissues()
{
  while : ; do
    cd .issues 2>/dev/null && return
    if [ "$(filesysid .)" = "$(filesysid /)" ] ; then
      error 'Not an issues repository (or any of the parent directories)'
    fi
    cd ..
  done
}

# Output the path of an issue given its SHA
# The scheme used for storing the issues is a two level directory
# structure where the first level consists of the first two SHA
# letters
#
# issue_path_full <SHA>
issue_path_full()
{
  local sha

  sha="$1"
  echo issues/"$(expr "$sha" : '\(..\)')/$(expr "$sha" : '..\(.*\)'$)"
}

# Output the path of an issue given its (possibly partial) SHA
# Abort with an error if the full path can not be uniquely resolved
# to an existing issue
# issue_path_part <SHA>
issue_path_part()
{
  local sha partial path

  sha="$1"
  partial=$(issue_path_full "$sha")
  path=$(echo "${partial}"*)
  test -d "$path" || error "Unknown or ambigious issue specification $sha"
  echo "$path"
}

# Given an issue path return its SHA
issue_sha()
{
    echo "$1" | sed 's/issues\/\(..\)\/\([^/]*\).*/\1\2/'
}

# Shorten a full SHA
short_sha()
{
  git rev-parse --short "$1"
}

# Start an issue transaction
trans_start()
{
  cdissues
  start_sha=$(git rev-parse HEAD)
}

# Abort an issue transaction and exit with an error
trans_abort()
{
  if [ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1 ; then
    git reset "$start_sha"
    git clean -qfd
    git checkout -- .
    rm -f issue-header issue-body comments-header comments-body create-body create-header update-body update-header
    rm -f milestone-body milestone-header mileres-body mileres-header timestats-header
    rm -f timeestimate-body timeestimate-header timespent-body timespent-header timestats-body
  fi
  echo 'Operation aborted' 1>&2
  exit 1
}

# Exit with an error if the specified prerequisite command
# cannot be executed
prerequisite_command()
{
  if ! $1 -help 2>/dev/null 1>&2 ; then
    cat <<EOF 1>&2
The $1 command is not available through the configured path.
Please install it and/or configure your PATH variable.
Command aborted.
EOF
    exit 1
  fi
}

# Commit an issue's changes
# commit <summary> <message> [<date>]
commit()
{
  commit_summary=$1
  shift
  commit_message=$1
  shift
  git commit --allow-empty -q -m "$commit_summary

$commit_message" "$@" || trans_abort
}

# Allow the user to edit the specified file
# Remove lines starting with '#'
# Succeed if at the resulting file is non-empty
edit()
{
  local file

  file="$1"
  touch "$file"
  cp "$file" "$file.new"
  echo "Opening editor..."
  ${VISUAL:-vi} "$file.new" || return 1
  grep -v '^#' "$file.new" >"$file.uncommented"
  mv "$file.uncommented" "$file.new"
  if ! test -s "$file.new" ; then
    echo 'Empty file' 1>&2
    rm -f "$file.new"
    return 1
  fi
  if diff -q "$file" "$file.new" >/dev/null 2>&1; then
    echo 'File was not changed' 1>&2
    rm -f "$file.new"
    return 1
  fi
  mv "$file.new" "$file"
}

# Pipe input through the user's pager
pager()
{
  ${PAGER:-more}
}

# init: Initialize a new issue repository {{{1
usage_init()
{
  cat <<\USAGE_new_EOF
gi init usage: git issue init [-e]
-e	Use existing project's Git repository
USAGE_new_EOF
  exit 2
}

sub_init()
{
  local existing

  while getopts e flag ; do
    case $flag in
    e)
      existing=1
      ;;
    ?)
      usage_init
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -d .issues && error 'An .issues directory is already present'
  mkdir .issues || error 'Unable to create .issues directory'
  cdissues
  if ! [ "$existing" ] ; then
    git init -q || error 'Unable to initialize Git directory'
  fi

  # Editing templates
  touch config || error 'Unable to create configuration file'
  mkdir templates || error 'Unable to create the templates directory'
  cat >templates/description <<\EOF

# Start with a one-line summary of the issue.  Leave a blank line and
# continue with the issue's detailed description.
#
# Remember:
# - Be precise
# - Be clear: explain how to reproduce the problem, step by step,
#   so others can reproduce the issue
# - Include only one problem per issue report
#
# Lines starting with '#' will be ignored, and an empty message aborts
# the issue addition.
EOF

  cat >templates/comment <<\EOF

# Please write here a comment regarding the issue.
# Keep the conversation constructive and polite.
# Lines starting with '#' will be ignored, and an empty message aborts
# the issue addition.
EOF
  cat >README.md <<\EOF
This is an distributed issue tracking repository based on Git.
Visit [git-issue](https://github.com/dspinellis/git-issue) for more information.
EOF
  git add config README.md templates/comment templates/description
  commit 'gi: Initialize issues repository' 'gi init'
  echo "Initialized empty issues repository in $(pwd)"
}

# new: Open a new issue {{{1
usage_new()
{
  cat <<\USAGE_new_EOF
gi new usage: git issue new [-s summary]
USAGE_new_EOF
  exit 2
}

sub_new()
{
  local summary sha path

  while getopts s:c: flag ; do
    case $flag in
    s)
      summary="$OPTARG"
      ;;
    c)
      create=$OPTARG
      ;;
    ?)
      usage_new
      ;;
    esac
  done
  shift $((OPTIND - 1));

  trans_start
  commit 'gi: Add issue' 'gi new mark'
  sha=$(git rev-parse HEAD)
  path=$(issue_path_full "$sha")
  mkdir -p "$path" || trans_abort
  echo open >"$path/tags" || trans_abort
  if [ "$summary" ] ; then
    echo "$summary" >"$path/description" || trans_abort
  else
    cp templates/description "$path/description" || trans_abort
    edit "$path/description" || trans_abort
  fi
  git add "$path/description" "$path/tags" || trans_abort
  commit 'gi: Add issue description' "gi new description $sha"
  echo "Added issue $(short_sha "$sha")"
  # export issue immediately
  if [ -n "$create" ] ; then
    # shellcheck disable=SC2086
    # Rationale: We want word splitting
    create_issue -n "$sha" $create
  fi
}

# show: Show the specified issue {{{1
usage_show()
{
  cat <<\USAGE_show_EOF
gi show usage: git issue show [-c] <sha>
-c	Show comments
USAGE_show_EOF
  exit 2
}

sub_show()
{
  local isha path comments rawdate rawest rawspent OPTIND

  while getopts c flag ; do
    case $flag in
    c)
      comments=1
      ;;
    ?)
      usage_show
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" || usage_show

  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  {
    # SHA, author, date
    echo "issue $isha"
    git show --no-patch --format='Author:	%an <%ae>
Date:	%aD' "$isha"

    # Imports
    for i in $(importsget "$isha") ; do
      local num
      num=$(echo "$i" | grep -o '/[0-9]\+$' | tr -d '/')
      if echo "$i" | grep -q '^github' ; then
        echo "GitHub issue: #$num at $i" | sed -e 's:/[0-9]\+$::' -e 's:github/::'
      else
        echo "GitLab issue: #$num at $i" | sed -e 's:/[0-9]\+$::' -e 's:gitlab/::'
      fi
    done

    # Due Date
    if [ -s "$path/duedate" ] ; then
      printf 'Due Date: '
      # Print date in rfc-3339 for consistency with git show
      rawdate=$(cat "$path/duedate")
      $DATEBIN --date="$rawdate" --rfc-3339=seconds
    fi

    # Time estimate
    if [ -s "$path/timeestimate" ] && [ -s "$path/timespent" ] ; then
      printf 'Time Spent/Time Estimated: '
      rawest=$(cat "$path/timeestimate")
      rawspent=$(cat "$path/timespent")
      # shellcheck disable=SC2016
      # SC2016: Expressions don't expand is single quotes, use double quotes for that
      # Rationale: We don't want expansion
      eval "echo $($DATEBIN --utc --date="@$rawspent" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')" |
      # Remove newline and trim unnecessary fields
      tr -d '\n' | sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //"
      printf '/ '
      # shellcheck disable=SC2016
      eval "echo $($DATEBIN --utc --date="@$rawest" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')" |
      sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //"
    elif [ -s "$path/timespent" ] ; then
      printf 'Time Spent: '
      # Print time in human readable format
      rawspent=$(cat "$path/timespent")
      # shellcheck disable=SC2016
      eval "echo $($DATEBIN --utc --date="@$rawspent" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')" |
      sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //"
    elif [ -s "$path/timeestimate" ] ; then
      printf 'Time Estimate: '
      # Print time in human readable format
      rawest=$(cat "$path/timeestimate")
      # shellcheck disable=SC2016
      eval "echo $($DATEBIN --utc --date="@$rawest" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')" |
      sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //"
    fi

    # Milestone
    if [ -s "$path/milestone" ] ; then
      printf 'Milestone: '
      cat "$path/milestone"
    fi

    # Weight
    if [ -s "$path/weight" ] ; then
      printf 'Weight: '
      cat "$path/weight"
    fi


    # Tags
    if [ -s "$path/tags" ] ; then
      printf 'Tags:'
      sed 's/^/	/' "$path/tags"
    fi

    # Watchers
    if [ -s "$path/watchers" ] ; then
      printf 'Watchers:'
      fmt "$path/watchers" | sed 's/^/	/'
    fi

    # Assignee
    if [ -r "$path/assignee" ] ; then
      printf 'Assigned-to:'
      sed 's/^/	/' "$path/assignee"
    fi

    # Description
    echo
    sed 's/^/    /' "$path/description"

    # Edit History
    echo
    printf '%s\n' 'Edit History:'
    git log --reverse --format="%aD by %an <%ae>" "$path/description" | fmt | sed 's/^/* /'

    # Comments
    test -n "$comments" || return
    git log --reverse --grep="^gi comment mark $isha" --format='%H' |
    while read -r csha ; do
      echo
      echo "comment $csha"
      git show --no-patch --format='Author:	%an <%ae>
Date:	%aD
' "$csha"
      sed 's/^/    /' "$path/comments/$csha"
    done
  } | pager
}

# clone: Clone the specified remote repository {{{1
usage_clone()
{
  cat <<\USAGE_clone_EOF
gi clone usage: git issue clone <URL> <local-dir>
USAGE_clone_EOF
  exit 2
}

sub_clone()
{
  test -n "$1" -a -n "$2" || usage_clone
  mkdir -p "$2" || error "Unable to create local directory"
  cd "$2" || error "Unable to change into local directory"
  git clone "$1" .issues
  echo "Cloned $1 into $2"
}

# milestone: set an issue's milestone {{{1
usage_milestone()
{
  cat <<\USAGE_tag_EOF
gi milestone usage: git issue milestone <sha> <milestone>
	git issue milestone -r <sha>
-r	Remove the issue's milestone
USAGE_tag_EOF
  exit 2
}

sub_milestone()
{
  local isha tag remove path milestone OPTIND

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      usage_milestone
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_milestone
  test -n "$remove" -a -n "$2" && usage_milestone

  milestone="$2"

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  if [ "$remove" ] ; then
    test -r "$path/milestone" || error "No milestone set"
    milestone=$(cat "$path/milestone")
    trans_start
    git rm "$path/milestone" >/dev/null || trans_abort
    commit "gi: Remove milestone" "gi milestone remove $milestone"
    echo "Removed milestone $milestone"
  else
    touch "$path/milestone" || error "Unable to modify milestone file"
    printf '%s\n' "$milestone" >"$path/milestone"
    trans_start
    git add "$path/milestone" || trans_abort
    commit "gi: Add milestone" "gi milestone add $milestone"
    echo "Added milestone $milestone"
  fi
}

# weight: set an issue's weight {{{1
usage_weight()
{
  cat <<\USAGE_tag_EOF
gi weight usage: git issue weight <sha> <weight>
	git issue weight -r <sha>
-r	Remove the issue's weight
USAGE_tag_EOF
  exit 2
}

sub_weight()
{
  local isha tag remove path weight OPTIND

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      usage_weight
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_weight
  test -n "$remove" -a -n "$2" && usage_weight
  weight="$2"
  if ! [ "$remove" ] ; then
    # weight is positive integer
    expr "$weight" : '[0-9]*$' > /dev/null || usage_weight
  fi

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  if [ "$remove" ] ; then
    test -r "$path/weight" || error "No weight set"
    weight=$(cat "$path/weight")
    trans_start
    git rm "$path/weight" >/dev/null || trans_abort
    commit "gi: Remove weight" "gi weight remove $weight"
    echo "Removed weight $weight"
  else
    touch "$path/weight" || error "Unable to modify weight file"
    printf '%s\n' "$weight" >"$path/weight"
    trans_start
    git add "$path/weight" || trans_abort
    commit "gi: Add weight" "gi weight add $weight"
    echo "Added weight $weight"
  fi
}

# duedate: set an issue's weight {{{1
usage_duedate()
{
  cat <<\USAGE_tag_EOF
gi duedate usage: git issue duedate <sha> <dd>
	git issue duedate -r <sha>
<dd>	date in format accepted by `date`
-r	Remove the issue's duedate
USAGE_tag_EOF
  exit 2
}

sub_duedate()
{
  local isha tag remove path duedate OPTIND

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      usage_duedate
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_duedate
  test -n "$remove" -a -n "$2" && usage_duedate
  # Date is stored in the ISO-8601 format
  duedate=$($DATEBIN --date="$2" --iso-8601=seconds) || usage_duedate
  if ! [ "$remove" ] ; then
    # Convert dates to utc for accurate comparison
    expr "$($DATEBIN --date="$duedate" --iso-8601=seconds --utc)" '>' "$($DATEBIN --date='now' --iso-8601=seconds --utc)" \
    > /dev/null || printf "Warning: duedate is in the past\n"
  fi

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  if [ "$remove" ] ; then
    test -r "$path/duedate" || error "No duedate set"
    duedate=$(cat "$path/duedate")
    trans_start
    git rm "$path/duedate" >/dev/null || trans_abort
    commit "gi: Remove duedate" "gi duedate remove $duedate"
    echo "Removed duedate $duedate"
  else
    touch "$path/duedate" || error "Unable to modify duedate file"
    printf '%s\n' "$duedate" >"$path/duedate"
    trans_start
    git add "$path/duedate" || trans_abort
    commit "gi: Add duedate" "gi duedate add $duedate"
    echo "Added duedate $duedate"
  fi
}

# timespent: set time spent on an issue {{{1
usage_timespent()
{
  cat <<\USAGE_tag_EOF
gi timespent usage: git issue timespent [-a] <sha> <ts>
-a	instead of replacing the time spent, add to it
	git issue timespent -r <sha>
<ts>	time interval in format accepted by `date`
-r	Remove the issue's timespent
USAGE_tag_EOF
  exit 2
}

sub_timespent()
{
  local isha tag remove path timespent add OPTIND

  while getopts ra flag ; do
    case $flag in
    a)
      add=1
      ;;
    r)
      remove=1
      ;;
    ?)
      usage_timespent
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_timespent
  test -n "$remove" -a -n "$add" && usage_timespent
  test -n "$remove" -a -n "$2" && usage_timespent
  # Timespent is stored in seconds
  timespent=$($DATEBIN --date="1970-1-1 +$2" --utc +%s)|| usage_timespent
  if ! [ "$remove" ] ; then
    # Check for negative time interval
    if [ "$timespent" -lt 0 ] ; then
      usage_timespent
    fi
  fi

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  if [ "$remove" ] ; then
    test -r "$path/timespent" || error "No time spent set"
    timespent=$(cat "$path/timespent")
    trans_start
    git rm "$path/timespent" >/dev/null || trans_abort
    commit "gi: Remove timespent" "gi timespent remove $timespent"
    echo "Removed timespent $timespent"
  else
    if [ "$add" ] ; then
      test -r "$path/timespent" || error "No time spent set"
      rawspent=$(cat "$path/timespent")
      # Add the existing time spent
      timespent=$((rawspent + timespent))
    fi
    touch "$path/timespent" || error "Unable to modify timespent file"
    printf '%s\n' "$timespent" >"$path/timespent"
    trans_start
    git add "$path/timespent" || trans_abort
    commit "gi: Add timespent" "gi timespent add $timespent"
    echo "Added timespent $timespent"
  fi
}

# timeestimate: set time spent on an issue {{{1
usage_timeestimate()
{
  cat <<\USAGE_tag_EOF
gi timeestimate usage: git issue timeestimate <sha> <te>
	git issue timeestimate -r <sha>
<te>	time interval in format accepted by `date`
-r	Remove the issue's time estimate
USAGE_tag_EOF
  exit 2
}

sub_timeestimate()
{
  local isha tag remove path timeestimate rawspent OPTIND

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      usage_timeestimate
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_timeestimate
  test -n "$remove" -a -n "$2" && usage_timeestimate
  # Timeestimate is stored in seconds
  timeestimate=$($DATEBIN --date="1970-1-1 +$2" --utc +%s)|| usage_timeestimate
  if ! [ "$remove" ] ; then
    # Check for negative time interval
    if [ "$timeestimate" -lt 0 ] ; then
      usage_timespent
    fi
  fi

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  if [ "$remove" ] ; then
    test -r "$path/timeestimate" || error "No time estimate set"
    timeestimate=$(cat "$path/timeestimate")
    trans_start
    git rm "$path/timeestimate" >/dev/null || trans_abort
    commit "gi: Remove timeestimate" "gi timeestimate remove $timeestimate"
    echo "Removed timeestimate $timeestimate"
  else
    touch "$path/timeestimate" || error "Unable to modify timeestimate file"
    printf '%s\n' "$timeestimate" >"$path/timeestimate"
    trans_start
    git add "$path/timeestimate" || trans_abort
    commit "gi: Add timeestimate" "gi timeestimate add $timeestimate"
    echo "Added timeestimate $timeestimate"
  fi
}



# assign: assign an issue to a person or remove assignment {{{1
usage_assignee()
{
  cat <<\USAGE_tag_EOF
gi assign usage: git issue assign [-r] <sha> <email> ...
-r	Remove the specified assignee
USAGE_tag_EOF
  exit 2
}

sub_assign()
{
  file_add_rm assignee assignee "$@"
}

# Generic file add/remove entry {{{1
# file_add_rm [-r] entry-name filename sha entry ...
file_add_rm()
{
  local usage name file isha tag remove path OPTIND

  name=$1
  shift
  file=$1
  shift
  usage=usage_$name

  while getopts r flag ; do
    case $flag in
    r)
      remove=1
      ;;
    ?)
      $usage
      ;;
    esac
  done
  shift $((OPTIND - 1));

  test -n "$1" -a -n "$2" || $usage

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha "$path")
  touch "$path/$file" || error "Unable to modify $file file"
  for entry in "$@" ; do
    if [ "$remove" ] ; then
      grep -Fvx "$entry" "$path/$file" >"$path/$file.new"
      if cmp "$path/$file" "$path/$file.new" >/dev/null 2>&1 ; then
	echo "No such $name entry: $entry" 1>&2
	rm "$path/$file.new"
	exit 1
      fi
      mv "$path/$file.new" "$path/$file"

      trans_start
      git add "$path/$file" || trans_abort
      echo "Removed $name $entry"
      if ! [ -s "$path/$file" ] ; then
        git rm -f "$path/$file" >/dev/null || trans_abort
      fi
      commit "gi: Remove $name" "gi $name remove $entry"
    else
      if grep -Fx "$entry" "$path/$file" >/dev/null ; then
	echo "Entry $entry already exists" 1>&2
	exit 1
      fi
      # Add entry in sorted order to avoid gratuitous updates when importing
      printf '%s\n' "$entry" |
      LC_ALL=C sort -m - "$path/$file" >"$path/$file.new"
      mv "$path/$file.new" "$path/$file"

      trans_start
      git add "$path/$file" || trans_abort
      commit "gi: Add $name" "gi $name add $entry"
      echo "Added $name $entry"
    fi
  done
}

# tag: Add or remove an issue tag {{{1
usage_tag()
{
  cat <<\USAGE_tag_EOF
gi tag usage: git issue tag [-r] <sha> <tag> ...
-r	Remove the specified tag
USAGE_tag_EOF
  exit 2
}

sub_tag()
{
  file_add_rm tag tags "$@"
}

# watcher: Add or remove an issue watcher {{{1
usage_watcher()
{
  cat <<\USAGE_watcher_EOF
gi watcher usage: git issue watcher [-r] <sha> <tag> ...
-r	Remove the specified watcher
USAGE_watcher_EOF
  exit 2
}

sub_watcher()
{
  file_add_rm watcher watchers "$@"
}

# comment: Comment on an issue {{{1
usage_comment()
{
  cat <<\USAGE_comment_EOF
gi comment usage: git issue comment <sha>
USAGE_comment_EOF
  exit 2
}

sub_comment()
{
  local isha csha path

  test -n "$1" || usage_comment

  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  mkdir -p "$path/comments" || error "Unable to create comments directory"
  trans_start
  commit 'gi: Add comment' "gi comment mark $isha"
  csha=$(git rev-parse HEAD)
  cp templates/comment "$path/comments/$csha" || trans_abort
  edit "$path/comments/$csha" || trans_abort
  git add "$path/comments/$csha" || trans_abort
  commit 'gi: Add comment message' "gi comment message $isha $csha"
  echo "Added comment $(short_sha "$csha")"
}

# edit: Edit an issue's description
usage_edit()
{
  cat <<\USAGE_edit_EOF
gi edit usage: git issue edit [-c] <sha>
USAGE_edit_EOF
  exit 2
}

sub_edit()
{
  local isha csha path comment fullpath OPTIND

  while getopts c flag ; do
    case $flag in
    c)
      comment=1
      ;;
    ?)
      usage_edit
      ;;
    esac
  done
 
  shift $((OPTIND - 1));
  test -n "$1" || usage_edit

  cdissues
  if [ -z "$comment" ] ; then
    # Edit Issue
    path=$(issue_path_part "$1") || exit
    isha=$(issue_sha "$path")

    trans_start
    edit "$path/description" || trans_abort
    git add "$path/description" || trans_abort
    commit 'gi: Edit issue description' "gi edit description $isha"
    echo "Edited issue $(short_sha "$isha")"
  else
    # Edit Comment
    commit=$(git show --format='%b' "$1" 2> /dev/null ) || error "Unknown or ambigious comment specification $1"
    # get issue sha
    isha=$(echo "$commit" | sed 's/gi comment mark //')
    echo "$isha" | grep -q '^[a-f0-9]\+$' || error "Not a comment sha."
    path=$(issue_path_part "$isha")
    # Get full comment sha
    csha=$(git rev-parse "$1")
    # shellcheck disable=SC2206
    # SC2128: Expanding an array without an index only gives the first element.
    edit "$path/comments/$csha" || trans_abort
    git add "$path/comments/$csha" || trans_abort
    commit 'gi: Edit comment' "gi edit comment $csha"
    echo "Edited comment $(short_sha "$csha")"
  fi

}


# shellcheck source=lib/git-issue/import-export.sh
. "$MY_LIB/import-export.sh"

# list: Show issues matching a tag {{{1
usage_list()
{
  cat <<\USAGE_list_EOF
gi list usage: git issue list [-a] [tag|milestone]
              git issue list [-a] -l formatstring [-o sort_field] [-r] [tag|milestone]
USAGE_list_EOF
  exit 2
}

# helper function for long listing format, each call proccesses a single issue
shortshow()
{

  local path formatstring sortfield id date duedate rawdate milestone weight assignee tags description rawest timeestimate rawspent timespent

  path=$1
  formatstring=$2
  sortfield=$3
  id=$4

  # Date
  date=$(git show --no-patch --format='%ai' "$id")

  # Milestone
  if [ -s "$path/milestone" ] ; then
    # Escape sed special chars before passing them
    milestone=$(fmt "$path/milestone"|sed -e 's/[\/&]/\\&/g')
  fi

  # Weight
  if [ -s "$path/weight" ] ; then
    weight=$(fmt "$path/weight")
  fi

  # Due Date
  if [ -s "$path/duedate" ] ; then
    rawdate=$(fmt "$path/duedate")
    # Print it in rfc-3339 for consistency with git show format
    duedate=$($DATEBIN --date="$rawdate" --rfc-3339=seconds)
  fi

  # Time Estimate
  if [ -s "$path/timeestimate" ] ; then
    rawest=$(cat "$path/timeestimate")
    # shellcheck disable=SC2016
    # SC2016: Expressions don't expand is single quotes, use double quotes for that
    # Rationale: We don't want expansion
    timeestimate=$(eval "echo $($DATEBIN --utc --date="@$rawest" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"|
    sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //")
  else
    timeestimate='-'
  fi

  # Time Spent
  if [ -s "$path/timespent" ] ; then
    rawspent=$(cat "$path/timespent")
    # shellcheck disable=SC2016
    timespent=$(eval "echo $($DATEBIN --utc --date="@$rawspent" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')"|
    sed -e "s/00 \(hours\|minutes\|seconds\) \?//g" -e "s/^0 days //")
  else
    timespent='-'
  fi

  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(tr '\n' ' ' < "$path/assignee"|sed -e 's/[\/&]/\\&/g')
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    tags=$(tr '\n' ' ' < "$path/tags"|sed -e 's/[\/&]/\\&/g')
  fi

  # Description
  description=$(head -n 1 "$path/description"|sed -e 's/[\/&]/\\&/g')

  # Print the field to sort by first, and remove it after sorting
  (echo "$sortfield"$'\002'"$formatstring") |

  sed -e s/%n/$'\001'/g \
  -e s/%i/"$id"/g \
  -e s/%c/"$date"/g \
  -e s/%d/"$duedate"/g \
  -e s/%e/"$timeestimate"/g \
  -e s/%s/"$timespent"/g \
  -e s/%M/"$milestone"/g \
  -e s/%w/"$weight"/g \
  -e s/%A/"$assignee"/g \
  -e s/%T/"$tags"/g \
  -e s/%D/"$description"/g |
  tr '\n' '\001'
  echo

}


sub_list()
{
  local all tag path id sortrev OPTIND

  while getopts al:o:r flag ; do
    case "$flag" in
    a)
      all=1
      ;;
    l)
      long=1
      formatstring="$OPTARG"
      ;;
    o)
      sortfield=$OPTARG
      if [ -z "$sortfield" ] ; then
        usage_list
      fi
      if ! expr "$sortfield" : '^%[icdeswMATD]$' > /dev/null ; then
        usage_list
      fi
      ;;
    r)
      sortrev="-r"
      ;;
    ?)
      usage_list
      ;;
    esac
  done

  case "$formatstring" in
    oneline)
      formatstring='ID: %i  Date: %c  Tags: %T  Desc: %D'
      ;;
    short)
      formatstring='ID: %i%nDate: %c%nDue Date: %d%nTags: %T%nDescription: %D'
      ;;
    compact)
      formatstring='ID: %i   Date: %c%nDue Date: %d   Weight: %w%nTags: %T   Milestone: %M%nDescription: %D'
      ;;
    medium)
      formatstring='ID: %i%nDate: %c%nDue Date: %d%nMilestone: %M%nWeight: %w%nTags: %T%nDescription: %D'
      ;;
    full)
      formatstring='ID: %i%nDate: %c%nDue Date: %d%nTime Spent: %s%nTime Estimate: %e%nAssignees: %A%nMilestone: %M%nWeight: %w%nTags: %T%nDescription: %D'
      ;;
  esac
  shift $((OPTIND - 1));
  tag="$1"
  : "${tag:=open}"
  cdissues
  test -d issues || exit 0
  find issues -type f -name tags -o -name milestone |
  if [ "$all" ] ; then
    cat
  else
    xargs grep -Flx "$tag"
  fi |
  # Convert list of tag or milestone file paths into the corresponding
  # directory and issue id
  sed 's/^\(.*\)\/[^\/]*$/\1/;s/\(issues\/\(..\)\/\(.....\).*\)/\1 \2\3/' |
  sort -u |
  if [ "$long" ] ; then

    while read -r path id ; do
      shortshow "$path" "$formatstring" "$sortfield" "$id"
    done |
    sort $sortrev |
    sed 's/^.*\x02//' |
    tr '\001' '\n'
  else
    while read -r path id ; do
      printf '%s' "$id "
      head -1 "$path/description"
    done |
    sort -k 2
  fi |
  tee results |
  pager

  # Error checking
  if ! [ -s results ] ; then
    echo 'No matching issues found' 1>&2
    exit 1
  fi
  rm -f results
}

# log: Show log of issue changes {{{1
usage_log()
{
  cat <<\USAGE_log_EOF
gi log usage: git issue log [-I issue-SHA] [git log options]
USAGE_log_EOF
  exit 2
}

sub_log()
{
  while getopts I: flag ; do
    case $flag in
    I)
      sha="$OPTARG"
      ;;
    ?)
      usage_log
      ;;
    esac
  done
  shift $((OPTIND - 1));

  cdissues
  if [ "$sha" ] ; then
    git log --grep="^gi new $sha" "$@"
  else
    git log "$@"
  fi

}

usage_filter()
{
  cat <<\USAGE_filter_EOF
gi filter usage: git issue filter-apply command
USAGE_filter_EOF
  exit 2
}

#filter-apply: Apply a filter (script or other command) for each issue
sub_filter()
{

  test -n "$1" || usage_filter
  command -v "$1" > /dev/null || test -x "$1" || error "$1 is not a recognized command."
  # Get absolute path
  #shellcheck disable=SC2164
  # SC2164: Use 'cd ... || exit' or 'cd ... || return' in case cd fails.
  abscmd="$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"
  shift
  cdissues
  test -d issues || error "There are no issues to filter."
  cd issues || trans_abort
  for i in */* ; do
    # In case the command changes directory
    cdissues
    #set environment variables for the command to use
    GI_SHA=$(echo "$i" | tr -d '/')
    GI_IMPORTS=$(importsget "$GI_SHA")
    GI_AUTHOR=$(git show --no-patch --format='%an' "$GI_SHA")
    GI_DATE=$(git show --no-patch --format='%aD' "$GI_SHA")
    export GI_SHA
    export GI_IMPORTS
    export GI_AUTHOR
    export GI_DATE
    cd "issues/$i" || trans_abort
    echo "Filtering issue $GI_SHA..."
    eval "$abscmd" "$@" || error "$abscmd returned non-zero exit status code. Aborting..."
  done
  echo
  echo 'Filter applied. To commit the results, run "gi git commit -a".'

}
# dump: Generate a json dump of all issues
sub_dump()
{
  local jstring path assignee tags title description duedate weight milestone timeestimate timespent

  shas=$(sub_list -l %i -o %c -a | sed '/^$/d' | tr '\n' ' ')

  cdissues
  {
    echo '{ "issues" : ['
    for sha in $shas ; do
      jstring="{\"sha\" : \"$sha\" }"
      path=$(issue_path_part "$sha") || exit
      # Get the attributes

      # Assignee
      if [ -r "$path/assignee" ] ; then
        assignee=$(tr '\n' ' ' < "$path/assignee")
        jstring=$(echo "$jstring" | jq --arg A "$assignee" -r '. + { assignee: $A }')
      fi

      # Tags
      if [ -s "$path/tags" ] ; then
        # format tags as json array
        tags=$(jq --slurp --raw-input 'split("\n")' "$path/tags")
        tags=$(echo "$tags" | jq 'map(select(. != ""))')
        if [ "$tags" != '[]' ] ; then
          jstring=$(echo "$jstring" | jq -r ". + { tags: $tags }")
        fi
      fi

      # Description
      # Title is the first line of description
      description=$(cat "$path/description")
      jstring=$(echo "$jstring" | jq --arg desc "$description" -r '. + { description: $desc }')

      # Due Date
      if [ -s "$path/duedate" ] ; then
        duedate=$($DATEBIN --iso-8601 --date="$(fmt "$path/duedate")")
        jstring=$(echo "$jstring" | jq --arg D "$duedate" -r '. + { due_date: $D }')
      fi

      # Weight
      if [ -s "$path/weight" ] ; then
        weight=$(fmt "$path/weight")
        jstring=$(echo "$jstring" | jq --arg W "$weight" -r '. + { weight: $W }')
      fi

      # Milestone
      if [ -s "$path/milestone" ] ; then
        milestone=$(fmt "$path/milestone")
        jstring=$(echo "$jstring" | jq --arg A "$milestone" -r '. + { milestone: $A }')
      fi

      # Time estimate/time spent
      if [ -s "$path/timeestimate" ] ; then
        timeestimate=$(fmt "$path/timeestimate")
        jstring=$(echo "$jstring" | jq --arg A "$timeestimate" -r '. + { timeestimate: $A }')
      fi

      if [ -s "$path/timespent" ] ; then
        timeestimate=$(fmt "$path/timespent")
        jstring=$(echo "$jstring" | jq --arg A "$timespent" -r '. + { timespent: $A }')
      fi

      if [ -d "$path/comments" ] ; then
        local csha
        cstring='[]'
        cshas=$(git log --reverse --grep="^gi comment mark $sha" --format='%H')
        for csha in $cshas ; do
          cstring=$(echo "$cstring" | jq --arg C "$(cat "$path/comments/$csha")" --arg S "$csha" '.+= [{ sha : $S , body: $C }]')
        done

        jstring=$(echo "$jstring" | jq -r ". + { comments: $cstring }")
      fi
      echo "$jstring" ','
      done
      echo '{} ] }'
  } | jq
}

# tags: List all used tags and their count {{{1
sub_tags()
{
  cdissues
  sort issues/*/*/tags | uniq -c | pager
}

# help: display help information {{{1
usage_help()
{
  cat <<\USAGE_help_EOF
gi help usage: git issue help
USAGE_help_EOF
  exit 2
}

sub_help()
{
  #
  # The following list is automatically created from README.md by running
  # make sync-docs
  # DO NOT EDIT IT HERE; UPDATE README.md instead
  #
  cat <<\USAGE_EOF
usage: git issue <command> [<args>]

The following commands are available:

Start an issue repository
   clone      Clone the specified remote repository
   init       Create a new issues repository in the current directory

Work with an issue
   new        Create a new open issue (with optional -s summary and -c "provider user repo" for github/gitlab export)
   show       Show specified issue (and its comments with -c)
   comment    Add an issue comment
   edit       Edit the specified issue's (or comment's with -c) description
   tag        Add (or remove with -r) a tag
   milestone  Specify (or remove with -r) the issue's milestone
   weight     Specify (or remove with -r) the issue's weight
   duedate    Specify (or remove with -r) the issue's due date
* timeestimate: Specify (or remove with -r) a time estimate for this issue
   timespent  Specify (or remove with -r) the time spent working on an issue so far
   assign     Assign (or remove -r) an issue to a person
   attach     Attach (or remove with -r) a file to an issue
   watcher    Add (or remove with -r) an issue watcher
   close      Remove the open tag, add the closed tag

Show multiple issues
   list       List open issues (or all with -a)
* list -l formatstring: This will list issues in the specified format, given as an argument to -l

Synchronize with remote repositories
   push       Update remote Git repository with local changes
   pull       Update local Git repository with remote changes
   import     Import/update GitHub/GitLab issues from the specified project
   create     Create the issue in the provided GitHub repository
   export     Export issues for the specified project
   exportall  Export all open issues in the database (-a to include closed ones) to GitHub/GitLab Useful for cloning whole repositories

Help and debug
   help       Display help information about git issue
   log        Output a log of changes made
   git        Run the specified Git command on the issues repository
USAGE_EOF
}

# Subcommand selection {{{1

subcommand="$1"
if ! [ "$subcommand" ] ; then
  sub_help
  exit 1
fi

shift
case "$subcommand" in

  filter-apply)
    sub_filter "$@"
    ;;
  dump)
    sub_dump "$@"
    ;;
  exportall)
    sub_exportall "$@"
    ;;
  export)
    export_issues "$@"
    ;;
  create)
    create_issue "$@"
    ;;
  init) # Initialize a new issue repository.
    sub_init "$@"
    ;;
  clone) # Clone specified remote directory.
    sub_clone "$@"
    ;;
  import) # Import issues from specified source
    sub_import "$@"
    ;;
  new) # Create a new issue and mark it as open.
    sub_new "$@"
    ;;
  list) # List the issues with the specified tag.
    sub_list "$@"
    ;;
  show) # Show specified issue (and its comments with -c).
    sub_show "$@"
    ;;
  comment) # Add an issue comment.
    sub_comment "$@"
    ;;
  tag) # Add (or remove with -r) a tag.
    sub_tag "$@"
    ;;
  assign) # Assign (or reassign) an issue to a person.
    sub_assign "$@"
    ;;
  attach) # Attach (or remove with -r) a file to an issue.
    echo 'Not implemented yet' 1>&2
    exit 1
    ;;
  watcher) # Add (or remove with -r) an issue watcher.
    sub_watcher "$@"
    ;;
  edit) # Edit the specified issue's summary or comment.
    sub_edit "$@"
    ;;
  close) # Remove the open tag from the issue, marking it as closed.
    sha="$1"
    sub_tag "$sha" closed
    sub_tag -r "$sha" open
    ;;
  help) # Display help information.
    sub_help
    ;;
  log) # Output log of changes made.
    sub_log "$@"
    ;;
  milestone) # Add (or remove with -r) a milestone
    sub_milestone "$@"
    ;;
   duedate) # Add (or remove with -r) a duedate
    sub_duedate "$@"
    ;;
   timespent) # Add (or remove with -r) the time spent
    sub_timespent "$@"
    ;;
   timeestimate) # Add (or remove with -r) the time estimate
    sub_timeestimate "$@"
    ;;
  weight) # Add (or remove with -r) a weight
    sub_weight "$@"
    ;;
  push) # Update remote repository with local changes.
    cdissues
    git push "$@"
    ;;
  pull) # Update local repository with remote changes.
    cdissues
    git pull "$@"
    ;;
  git) # Run the specified Git command on the issues repository.
    cdissues
    git "$@"
    ;;
  tags) # List all tags
    sub_tags
    ;;
  *)
    # Default to help.
    sub_help
    exit 1
    ;;
esac
