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

# User agent string
USER_AGENT=https://github.com/dspinellis/git-issue/tree/ba82a93

# Exit after displaying the specified error
error()
{
  echo "$1" 1>&2
  exit 1
}

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
    if [ $(filesysid .) = $(filesysid /) ] ; then
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
  echo issues/$(expr $sha : '\(..\)')/$(expr $sha : '..\(.*\)'$)
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
  path=$(echo ${partial}*)
  test -d "$path" || error "Unknown or ambigious issue specification $sha"
  echo $path
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
  git reset $start_sha
  git clean -qfd
  git checkout -- .
  rm -f gh-issue-header gh-issue-body gh-comments-header gh-comments-body
  echo 'Operation aborted' 1>&2
  exit 1
}

# Exit with an error if the specified prerequisite command
# cannot be executed
prerequisite_command()
{
  if ! $1 -help 2>/dev/null 1>&2 ; then
    cat <<EOF 1>&2
The $1 command is not availabe through the configured path.
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
  sed -i.original '/^#/d' "$file.new"
  rm -f "$file.new.original"
  if [ $(grep -c . "$file.new") -eq 0 ] ; then
    echo 'Empty file' 1>&2
    rm -f "$file.new"
    return 1
  fi
  if [ $(diff "$file" "$file.new" > /dev/null 2>&1) ]; then
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
  shift $(($OPTIND - 1));

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

  while getopts s: flag ; do
    case $flag in
    s)
      summary="$OPTARG"
      ;;
    ?)
      usage_new
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  trans_start
  commit 'gi: Add issue' 'gi new mark'
  sha=$(git rev-parse HEAD)
  path=$(issue_path_full $sha)
  mkdir -p $path || trans_abort
  echo open >$path/tags || trans_abort
  if [ "$summary" ] ; then
    echo "$summary" >$path/description || trans_abort
  else
    cp templates/description $path/description || trans_abort
    edit $path/description || trans_abort
  fi
  git add $path/description $path/tags || trans_abort
  commit 'gi: Add issue description' "gi new description $sha"
  echo "Added issue $(short_sha $sha)"
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
  local isha path comments

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
  shift $(($OPTIND - 1));

  test -n "$1" || usage_show

  cdissues
  path=$(issue_path_part $1) || exit
  isha=$(issue_sha $path)
  {
    # SHA, author, date
    echo "issue $isha"
    git show --no-patch --format='Author:	%an <%ae>
Date:	%aD' $isha

    # Milestone
    if [ -s $path/milestone ] ; then
      printf 'Milestone: '
      cat $path/milestone
    fi

    # Tags
    if [ -s $path/tags ] ; then
      printf 'Tags:'
      sed 's/^/	/' $path/tags
    fi

    # Watchers
    if [ -s $path/watchers ] ; then
      printf 'Watchers:'
      fmt $path/watchers | sed 's/^/	/'
    fi

    # Assignee
    if [ -r $path/assignee ] ; then
      printf 'Assigned-to:'
      sed 's/^/	/' $path/assignee
    fi

    # Description
    echo
    sed 's/^/    /' $path/description

    # Edit History
    echo
    printf '%s\n' 'Edit History:'
    git log --reverse --format="%aD by %an <%ae>" $path/description | fmt | sed 's/^/* /'

    # Comments
    test -n "$comments" || return
    git log --reverse --grep="^gi comment mark $isha" --format='%H' |
    while read csha ; do
      echo
      echo "comment $csha"
      git show --no-patch --format='Author:	%an <%ae>
Date:	%aD
' $csha
      sed 's/^/    /' $path/comments/$csha
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
  cd "$2"
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
  local isha tag remove path milestone

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
  shift $(($OPTIND - 1));

  test -n "$1" -a -n "$2$remove" || usage_milestone
  test -n "$remove" -a -n "$2" && usage_milestone

  milestone="$2"

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha $path)
  if [ "$remove" ] ; then
    test -r $path/milestone || error "No milestone set"
    milestone=$(cat $path/milestone)
    trans_start
    git rm $path/milestone >/dev/null || trans_abort
    commit "gi: Remove milestone" "gi milestone remove $milestone"
    echo "Removed milestone $milestone"
  else
    touch $path/milestone || error "Unable to modify milestone file"
    printf "%s\n" "$milestone" >$path/milestone
    trans_start
    git add $path/milestone || trans_abort
    commit "gi: Add milestone" "gi milestone add $milestone"
    echo "Added milestone $milestone"
  fi
}


# assign: assign an issue to a person or remove assignment {{{1
usage_assign()
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
  local usage name file isha tag remove path

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
  shift $(($OPTIND - 1));

  test -n "$1" -a -n "$2" || $usage

  cdissues
  path=$(issue_path_part "$1") || exit
  shift
  isha=$(issue_sha $path)
  touch $path/$file || error "Unable to modify $file file"
  for entry in "$@" ; do
    if [ "$remove" ] ; then
      fgrep -vx "$entry" $path/$file >$path/$file.new
      if cmp $path/$file $path/$file.new >/dev/null 2>&1 ; then
	echo "No such $name entry: $entry" 1>&2
	rm $path/$file.new
	exit 1
      fi
      mv $path/$file.new $path/$file

      trans_start
      git add $path/$file || trans_abort
      commit "gi: Remove $name" "gi $name remove $entry"
      echo "Removed $name $entry"
    else
      if fgrep -x "$entry" $path/$file >/dev/null ; then
	echo "Entry $entry already exists" 1>&2
	exit 1
      fi
      # Add entry in sorted order to avoid gratuitous updates when importing
      printf "%s\n" "$entry" |
      LC_ALL=C sort -m - $path/$file >$path/$file.new
      mv $path/$file.new $path/$file

      trans_start
      git add $path/$file || trans_abort
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
  path=$(issue_path_part $1) || exit
  isha=$(issue_sha $path)
  mkdir -p $path/comments || error "Unable to create comments directory"
  trans_start
  commit 'gi: Add comment' "gi comment mark $isha"
  csha=$(git rev-parse HEAD)
  cp templates/comment $path/comments/$csha || trans_abort
  edit $path/comments/$csha || trans_abort
  git add $path/comments/$csha || trans_abort
  commit 'gi: Add comment message' "gi comment message $isha $csha"
  echo "Added comment $(short_sha $csha)"
}

# edit: Edit an issue's description
usage_edit()
{
  cat <<\USAGE_edit_EOF
gi comment usage: git issue edit <sha>
USAGE_edit_EOF
  exit 2
}

sub_edit()
{
  local isha csha path

  test -n "$1" || usage_edit

  cdissues
  path=$(issue_path_part $1) || exit
  isha=$(issue_sha $path)

  trans_start
  edit $path/description || trans_abort
  git add $path/description || trans_abort
  commit 'gi: Edit issue description' "gi edit description $isha"
  echo "Edited issue $(short_sha $isha)"
}

# import: import issues from GitHub {{{1
usage_import()
{
  cat <<\USAGE_import_EOF
gi import usage: git issue import provider user repo
Example: git issue import github torvalds linux
USAGE_import_EOF
  exit 2
}

# Get a page using the GitHub API; abort transaction on error
# Header is saved in the file gh-$prefix-header; body in gh-$prefix-body
gh_api_get()
{
  local url prefix

  url="$1"
  prefix="$2"

  if ! curl $GI_CURL_ARGS -A "$USER_AGENT" -s \
    -o gh-$prefix-body -D gh-$prefix-header "$url" ; then
    echo 'GitHub connection failed' 1>&2
    trans_abort
  fi

  if ! grep -q '^Status: 200' gh-$prefix-header ; then
    echo 'GitHub API communication failure' 1>&2
    echo "URL: $url" 1>&2
    if grep -q '^Status: 4' gh-$prefix-header ; then
      jq -r '.message' gh-$prefix-body 1>&2
    fi
    trans_abort
  fi
}

# Import GitHub comments for the specified issue
# gh_import_comments  <user> <repo> <issue_number> <issue_sha>
gh_import_comments()
{
  local user repo issue_number isha
  local i endpoint comment_id import_dir csha

  user="$1"
  shift
  repo="$1"
  shift
  issue_number="$1"
  shift
  isha="$1"
  shift

  endpoint="https://api.github.com/repos/$user/$repo/issues/$issue_number/comments"
  while true ; do
    gh_api_get "$endpoint" comments

    # For each comment in the gh-comments-body file
    for i in $(seq 0 $(($(jq '. | length' gh-comments-body) - 1)) ) ; do
      comment_id=$(jq ".[$i].id" gh-comments-body)

      # See if comment already there
      import_dir="imports/github/$user/$repo/$issue_number/comments"
      if [ -r "$import_dir/$comment_id" ] ; then
	csha=$(cat "$import_dir/$comment_id")
      else
	name=$(jq -r ".[$i].user.login" gh-comments-body)
	GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-comments-body) \
	  commit 'gi: Add comment' "gi comment mark $isha" \
	  --author="$name <$name@users.noreply.github.com>"
	csha=$(git rev-parse HEAD)
      fi

      path=$(issue_path_full $isha)/comments
      mkdir -p $path || trans_abort
      mkdir -p $import_dir || trans_abort


      # Add issue import number to allow future updates
      echo $csha >"$import_dir/$comment_id"

      # Create comment body
      jq -r ".[$i].body" gh-comments-body >/dev/null || trans_abort
      jq -r ".[$i].body" gh-comments-body |
      tr -d \\r >$path/$csha

      git add $path/$csha $import_dir/$comment_id || trans_abort
      if ! git diff --quiet HEAD ; then
	local name html_url
	name=$(jq -r ".[$i].user.login" gh-comments-body)
	html_url=$(jq -r ".[$i].html_url" gh-comments-body)
	GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-comments-body) \
	  commit 'gi: Import comment message' "gi comment message $isha $csha
Comment URL: $html_url" \
	  --author="$name <$name@users.noreply.github.com>"
	echo "Imported/updated issue #$issue_number comment $comment_id as $(short_sha $csha)"
      fi
    done # For all comments on page

    # Return if no more pages
    if ! grep -q '^Link:.*rel="next"' gh-comments-header ; then
      break
    fi

    # Move to next point
    endpoint=$(gh_next_page_url comments)
  done
}

# Import GitHub issues stored in the file gh-issue-body as JSON data
# gh_import_issues user repo
gh_import_issues()
{
  local user repo
  local i issue_number import_dir sha path name

  user="$1"
  repo="$2"

  # For each issue in the gh-issue-body file
  for i in $(seq 0 $(($(jq '. | length' gh-issue-body) - 1)) ) ; do
    issue_number=$(jq ".[$i].number" gh-issue-body)

    # See if issue already there
    import_dir="imports/github/$user/$repo/$issue_number"
    if [ -d "$import_dir" ] ; then
      sha=$(cat "$import_dir/sha")
    else
      name=$(jq -r ".[$i].user.login" gh-issue-body)
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-issue-body) \
      commit 'gi: Add issue' 'gi new mark' \
	--author="$name <$name@users.noreply.github.com>"
      sha=$(git rev-parse HEAD)
    fi

    path=$(issue_path_full $sha)
    mkdir -p $path || trans_abort
    mkdir -p $import_dir || trans_abort

    # Add issue import number to allow future updates
    echo $sha >"$import_dir/sha"

    # Create tags (in sorted order to avoid gratuitous updates)
    {
      jq -r ".[$i].state" gh-issue-body
      jq -r ".[$i].labels[] | .name" gh-issue-body
    } |
    LC_ALL=C sort >$path/tags || trans_abort

    # Create assignees (in sorted order to avoid gratuitous updates)
    jq -r ".[$i].assignees[] | .login" gh-issue-body |
    LC_ALL=C sort >$path/assignee || trans_abort

    if [ -s $path/assignee ] ; then
      git add $path/assignee || trans_abort
    else
      rm -f $path/assignee
    fi

    # Obtain milestone
    if [ $(jq ".[$i].milestone" gh-issue-body) = null ] ; then
      if [ -r $path/milestone ] ; then
	git rm $path/milestone || trans_abort
      fi
    else
      jq -r ".[$i].milestone" gh-issue-body >$path/milestone || trans_abort
      git add $path/milestone || trans_abort
    fi

    # Create description
    jq -r ".[$i].title" gh-issue-body >/dev/null || trans_abort
    jq -r ".[$i].body" gh-issue-body >/dev/null || trans_abort
    {
      jq -r ".[$i].title" gh-issue-body
      echo
      jq -r ".[$i].body" gh-issue-body
    } |
    tr -d \\r >$path/description

    git add $path/description $path/tags imports || trans_abort
    if ! git diff --quiet HEAD ; then
      name=${name:-$(jq -r ".[$i].user.login" gh-issue-body)}
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-issue-body) \
	commit "gi: Import issue #$issue_number from GitHub" \
	"Issue URL: https://github.com/$user/$repo/issues/$issue_number" \
	--author="$name <$name@users.noreply.github.com>"
      echo "Imported/updated issue #$issue_number as $(short_sha $sha)"
    fi

    # Import issue comments
    gh_import_comments "$user" "$repo" "$issue_number" $sha
  done
}

# Return the next page API URL specified in the header with the specified prefix
# Header examples (easy and tricky)
# Link: <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="next", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="last", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="first"
# Link: <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="prev", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="next", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="last", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="first"
gh_next_page_url()
{
  sed -n '
:again
# Print "next" link
# This works only for the first element of the Link header
s/^Link:.<\([^>]*\)>; rel="next".*/\1/p
# If substitution worked branch to end of script
t
# Remove first element of the Link header and retry
s/^Link: <[^>]*>; rel="[^"]*", */Link: /
t again
' gh-$1-header
}

# Import issues from specified source (currently github)
sub_import()
{
  local endpoint user repo begin_sha

  test "$1" = github -a -n "$2" -a -n "$3" || usage_import
  user="$2"
  repo="$3"

  cdissues

  prerequisite_command jq
  prerequisite_command curl

  begin_sha=$(git rev-parse HEAD)

  # Process GitHub issues page by page
  trans_start
  mkdir -p "imports/github/$user/$repo"
  endpoint="https://api.github.com/repos/$user/$repo/issues?state=all"
  while true ; do
    gh_api_get "$endpoint" issue
    gh_import_issues "$user" "$repo"

    # Return if no more pages
    if ! grep -q '^Link:.*rel="next"' gh-issue-header ; then
      break
    fi

    # Move to next point
    endpoint=$(gh_next_page_url issue)
  done

  rm -f gh-issue-header gh-issue-body gh-comments-header gh-comments-body

  # Mark last import SHA, so we can use this for merging 
  if [ $begin_sha != $(git rev-parse HEAD) ] ; then
    local checkpoint="imports/github/$user/$repo/checkpoint"
    git rev-parse HEAD >"$checkpoint"
    git add "$checkpoint"
    commit "gi: Import issues from GitHub checkpoint" \
    "Issues URL: https://github.com/$user/$repo/issues"
  fi
}

# list: Show issues matching a tag {{{1
usage_list()
{
  cat <<\USAGE_list_EOF
gi new usage: git issue list [-a] [tag|milestone]
USAGE_list_EOF
  exit 2
}

sub_list()
{
  local all tag path id

  while getopts a flag ; do
    case $flag in
    a)
      all=1
      ;;
    ?)
      usage_list
      ;;
    esac
  done
  shift $(($OPTIND - 1));

  tag="$1"
  : ${tag:=open}
  cdissues
  test -d issues || exit 0
  find issues -type f -name tags -o -name milestone |
  if [ "$all" ] ; then
    cat
  else
    xargs fgrep -lx "$tag"
  fi |
  # Convert list of tag or milestone file paths into the corresponding
  # directory and issue id
  sed 's/^\(.*\)\/[^\/]*$/\1/;s/\(issues\/\(..\)\/\(.....\).*\)/\1 \2\3/' |
  sort -u |
  while read path id ; do
    printf '%s' "$id "
    head -1 $path/description
  done |
  sort -k 2 |
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
gi new usage: git issue log [-I issue-SHA] [git log options]
USAGE_log_EOF
  exit 2
}

sub_log()
{
  local grep_arg

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
  shift $(($OPTIND - 1));

  cdissues
  if [ "$sha" ] ; then
    git log --grep="^gi new $sha" "$@"
  else
    git log "$@"
  fi

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
   new        Create a new open issue (with optional -s summary)
   show       Show specified issue (and its comments with -c)
   comment    Add an issue comment
   edit       Edit the specified issue's description
   tag        Add (or remove with -r) a tag
   milestone  Specify (or remove with -r) the issue's milestone
   assign     Assign (or remove -r) an issue to a person
   attach     Attach (or remove with -r) a file to an issue
   watcher    Add (or remove with -r) an issue watcher
   close      Remove the open tag, add the closed tag

Show multiple issues
   list       List open issues (or all with -a)

Synchronize with remote repositories
   push       Update remote Git repository with local changes
   pull       Update local Git repository with remote changes
   import     Import/update GitHub issues from the specified project

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
