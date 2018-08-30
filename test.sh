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
# along with gi.  If not, see <http://www.gnu.org/licenses/>.
#

# Display a test's result
message()
{
  local okfail

  okfail=$1
  shift
  if [ "$1" ] ; then
    echo "$okfail $ntest - $*"
  else
    echo "$okfail $ntest - $testname"
  fi |
  sed "s/$gi_re/gi/"
}

ok()
{
  message ok $*
}

fail()
{
  printf "$ntest " >>$TopDir/failure
  message fail $*
}

# Test specified command, which should succeed
try()
{
  local exit_code

  ntest=$(expr $ntest + 1)
  echo "Test $ntest: $*" >>$TopDir/error.log 
  $* >/dev/null 2>>$TopDir/error.log 
  exit_code=$?
  cd .issues
  if git status | grep 'not staged' >/dev/null ; then
    fail staging $*
  else
    ok staging $*
  fi
  cd ..
  start
  if [ $exit_code = 0 ] ; then
    ok $*
  else
    fail $*
  fi
}

# Test specified command, which should fail
ntry()
{
  ntest=$(expr $ntest + 1)
  $* >/dev/null 2>&1
  if [ $? != 0 ] ; then
    ok "fail $*"
  else
    fail "fail $*"
  fi
}

# grep for the specified pattern, which should be found
# Does not increment ntest, because it is executed as a separate process
try_grep()
{
  test -z "$testname" && echo "Test $ntest: grep $@" >>$TopDir/error.log
  grep "$@" >/dev/null 2>&1
  if [ $? = 0 ] ; then
    ok "grep $@"
  else
    fail "grep $@"
  fi
}

# grep for the specified pattern, which should not be found
# Does not increment ntest, because it is executed as a separate process
try_ngrep()
{
  test -z "$testname" && echo "Test $ntest: ! grep $@" >>$TopDir/error.log
  grep "$@" >/dev/null 2>&1
  if [ $? != 0 ] ; then
    ok "not grep $1"
  else
    fail "not grep $1"
  fi
}

# Start a new test with the specified description
start()
{
  ntest=$(expr $ntest + 1)
  testname="$@"
  test -n "$testname" && echo "Test $ntest: $*" >>$TopDir/error.log
}

# Fold header continuation lines
header_continuation()
{
sed -n '
# Header
/^[^ 	]/ {
  # Print previous hold space
  x
  s/\n//g
  /^./p
  x
  # Keep in hold space
  h
}
# Continuation
/^[ 	]/ {
  # Append to hold space
  H
}
$ {
  # Print previous hold space
  x
  s/\n/ /g
  /^./p
}
'
}

TopDir=$(mktemp -d)
{
  jq --version
  curl --version
  echo "Test artifacts saved in $TopDir"
} 1>&2

# Setup GitHub authentication token for Travis CI for curl version >= 7.55
# The GH_TOKEN environment variable with the secret token is specified in
# https://travis-ci.org/dspinellis/git-issue/settings
if [ -n "$GH_TOKEN" ] &&  curl --version | awk '/curl/{exit $2 >= "7.55" ? 0 : 1}' ; then
  echo "Authorization: token $GH_TOKEN" >$HOME/.token
  export GI_CURL_ARGS="-H @$HOME/.token"
  echo "Set GI_CURL_ARGS to $GI_CURL_ARGS using GH_TOKEN"
fi

echo 'TAP version 13'
ntest=0
gi=$(pwd)/git-issue.sh
gi_re=$(echo $gi | sed 's/[^0-9A-Za-z]/\\&/g')

start sync-docs
GenFiles="git-issue.sh git-issue.1"
sh sync-docs.sh --no-user-agent
Status=$(git status --porcelain -- $GenFiles)
if [ -z "$Status" ]; then
    ok "make sync-docs left $GenFiles as committed"
else
    fail "make sync-docs changed $GenFiles"
    git diff -- $GenFiles >>$TopDir/error.log
    git checkout -- $GenFiles
fi

cd $TopDir

mkdir testdir
cd testdir

try $gi init
try $gi list

start ; $gi list $issue | try_ngrep .

# New
try $gi new -s 'First-issue'
start ; $gi list | try_grep 'First-issue'

# New with editor
export VISUAL='mv ../issue-desc '

# Empty summary/description should fail
touch issue-desc
ntry $gi new

cat <<EOF >issue-desc
Second issue

Line in description
EOF
try $gi new

issue=$($gi list | awk '/Second issue/{print $1}')

# Show
start ; $gi show $issue | try_grep 'Second issue'
start ; $gi show $issue | try_grep 'Line in description'
start ; $gi show $issue | try_grep '^Author:'
start ; $gi show $issue | header_continuation | try_grep '^Tags:[ 	]*open'
ntry $gi show xyzzy

# Edit

# Unmodified issue should fail
ntry $gi edit $issue

cat <<EOF >issue-desc
Second issue

Modified line in description
EOF
try $gi edit $issue
start ; $gi show $issue | try_grep 'Second issue'
start ; $gi show $issue | try_grep 'Modified line in description'
start ; $gi show $issue | try_ngrep 'Line in description'

export VISUAL=

# Comment
start
cat <<EOF >comment
Comment first line
comment second line
EOF
export VISUAL='mv ../comment '; try $gi comment $issue
export VISUAL=
start ; $gi show -c $issue | try_grep 'comment second line'

# Assign
try $gi assign $issue joe@example.com
ntry $gi assign $issue joe@example.com
start ; $gi show $issue | header_continuation | try_grep '^Assigned-to:[ 	]joe@example.com'
try $gi assign $issue jane@example.com
start ; $gi show $issue | header_continuation | try_grep '^Assigned-to:.*jane@example.com'
start ; $gi show $issue | header_continuation | try_grep '^Assigned-to:.*joe@example.com'
try $gi assign -r $issue joe@example.com
start ; $gi show $issue | header_continuation | try_ngrep '^Assigned-to:.*joe@example.com'
ntry $gi assign -r $issue joe@example.com
try $gi assign -r $issue jane@example.com
start ; $gi show $issue | header_continuation | try_ngrep '^Assigned-to:.*jane@example.com'
try $gi assign $issue joe@example.com

# Watchers
try $gi watcher $issue jane@example.com
start ; $gi show $issue | header_continuation | try_grep '^Watchers:[ 	]jane@example.com'
try $gi watcher $issue alice@example.com
ntry $gi watcher $issue alice@example.com
start ; $gi show $issue | header_continuation | try_grep '^Watchers:.*jane@example.com'
start ; $gi show $issue | header_continuation | try_grep '^Watchers:.*alice@example.com'
try $gi watcher -r $issue alice@example.com
start ; $gi show $issue | header_continuation | try_ngrep '^Watchers:.*alice@example.com'
try $gi watcher $issue alice@example.com

# Tags (most also tested through watchers)
try $gi tag $issue feature
start ; $gi show $issue | header_continuation | try_grep '^Tags:.*feature'
ntry $gi tag $issue feature

# List by tag
start ; $gi list feature | try_grep 'Second issue'
start ; $gi list open | try_grep 'First-issue'
start ; $gi list feature | try_ngrep 'First-issue'
try $gi tag -r $issue feature
start ; $gi list feature | try_ngrep 'Second issue'
try $gi tag $issue feature

# close
try $gi close $issue
start ; $gi list | try_ngrep 'Second issue'
start ; $gi list closed | try_grep 'Second issue'

# log
try $gi log
start ; n=$($gi log | tee foo | grep -c gi:)
try test $n -ge 18

# clone
# Required in order to allow a push to a non-bare repo
$gi git config --add receive.denyCurrentBranch ignore
cd ..
rm -rf testdir2
mkdir testdir2
cd testdir2
git clone ../testdir/.issues/ 2>/dev/null
start ; $gi show $issue | header_continuation | try_grep '^Watchers:.*alice@example.com'
start ; $gi show $issue | header_continuation | try_grep '^Tags:.*feature'
start ; $gi show $issue | header_continuation | try_grep '^Assigned-to:.*joe@example.com'
start ; $gi show $issue | try_grep 'Second issue'
start ; $gi show $issue | try_grep 'Modified line in description'
start ; $gi show $issue | try_grep '^Author:'
start ; $gi show $issue | header_continuation | try_grep '^Tags:.*closed'

# Push and pull
try $gi tag $issue cloned
try $gi push
cd ../testdir
$gi git reset --hard >/dev/null # Required, because we pushed to a non-bare repo
start ; $gi show $issue | header_continuation | try_grep '^Tags:.*cloned'

# Pull
try $gi tag $issue modified-upstream
cd ../testdir2
try $gi pull
$gi show $issue | try_grep modified-upstream
cd ../testdir

if [ -z "$GI_CURL_ARGS" ] ; then
  echo "Skipping import tests due to lack of GitHub authentication token."
else
  # Import
  try $gi import github dspinellis git-issue-test-issues
  start ; $gi list | try_grep 'An open issue on GitHub with a description and comments'
  # Closed issues
  start ; $gi list | try_grep -v 'A closed issue on GitHub without description'
  start ; $gi list -a | try_grep 'A closed issue on GitHub without description'
  # Description and comments
  issue=$($gi list | awk '/An open issue on GitHub with a description and comments/ {print $1}')
  start ; $gi show $issue | try_grep '^ *line 1$'
  start ; $gi show $issue | try_grep '^ *line 2$'
  start ; $gi show $issue | try_grep 'Line 3 with special characters "'\''<>|\$'
  start ; $gi show -c $issue | try_grep '^ *comment 1 line 1$'
  start ; $gi show -c $issue | try_grep '^ *comment 1 line 2$'
  start ; $gi show -c $issue | try_grep '^ *comment 2$'
  start ; $gi show -c $issue | try_grep '^ *comment 4$'
  # Assignees and tags
  issue=$($gi list | awk '/An open issue on GitHub with assignees and tags/ {print $1}')
  start ; $gi show $issue | try_grep 'good first issue'
  start ; $gi show $issue | header_continuation | try_grep 'Assigned-to:[ 	]*dspinellis'
  # Import should be idempotent
  before=$(cd .issues ; git rev-parse --short HEAD)
  try $gi import github dspinellis git-issue-test-issues
  after=$(cd .issues ; git rev-parse --short HEAD)
  try test $before = $after
fi

if ! [ -r $TopDir/failure ]; then
  echo "All tests passed!"
  exit 0
else
  echo "Some test(s) failed: $(cat $TopDir/failure)"
  if [ -n "$TRAVIS_OS_NAME" ] ; then
    echo 'Error output follows' 1>&2
    cat $TopDir/error.log 1>&2
  else
    echo "Error output is in $TopDir/error.log"
  fi
  exit 1
fi
