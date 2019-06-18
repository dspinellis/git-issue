#! /bin/sh
# shellcheck disable=2039
# SC2039: In POSIX sh, 'local' is undefined

# import: import issues from GitHub {{{1
usage_import()
{
  cat <<\USAGE_import_EOF
gi import usage: git issue import provider user repo
Example: git issue import github torvalds linux
USAGE_import_EOF
  exit 2
}

# export: export issues to GitHub {{{1
usage_export()
{
  cat <<\USAGE_import_EOF
gi export usage: git issue export provider user repo
Example: git issue export github torvalds linux
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

  if ! curl -H "$GI_CURL_AUTH" -A "$USER_AGENT" -s \
    -o "gh-$prefix-body" -D "gh-$prefix-header" "$url" ; then
    echo 'GitHub connection failed' 1>&2
    trans_abort
  fi

  if ! grep -q '^Status: 200' "gh-$prefix-header" ; then
    echo 'GitHub API communication failure' 1>&2
    echo "URL: $url" 1>&2
    if grep -q '^Status: 4' "gh-$prefix-header" ; then
      jq -r '.message' "gh-$prefix-body" 1>&2
    fi
    trans_abort
  fi
}

# POST, PATCH or PUT data using the GitHub API; abort transaction on error
# Header is saved in the file gh-$prefix-header; body in gh-$prefix-body
gh_api_send()
{
  local url prefix data mode

  url="$1"
  prefix="$2"
  data="$3"
  mode=${4:-"POST"}
  if [ "$mode" = 'PATCH' ] ; then
    curl_mode='--request PATCH'
  elif [ "$mode" = 'PUT' ] ; then
    curl_mode='--request PUT'
  elif [ "$mode" = 'POST' ] ; then
    curl_mode=''
  else
    error "incorrect gh_api_send() mode: $mode"
  fi

  # shellcheck disable=SC2086
  # SC2086: Double quote to prevent globbing and word splitting.
  # Rationale: GI_CURL_ARGS and curl_mode indeed require splitting
  if ! curl -H "$GI_CURL_AUTH" -A "$USER_AGENT" -s \
    -o "gh-$prefix-body" -D "gh-$prefix-header" $curl_mode --data "$data" "$url" ; then
    echo 'GitHub connection failed' 1>&2
    trans_abort
  fi

  if ! grep -q '^Status: 20[0-9]' "gh-$prefix-header" ; then
    echo 'GitHub API communication failure' 1>&2
    echo "URL: $url" 1>&2
    echo "Data: $data" 1>&2
    if grep -q '^Status: 4' "gh-$prefix-header" ; then
      jq -r '.message' "gh-$prefix-body" 1>&2
    fi
    trans_abort
  fi
}

# Create an issue in Github, based on a local one
gh_create_issue()
{
  local isha path assignee description url user repo nodelete
     
  while getopts n flag ; do    
    case $flag in    
    n)    
      nodelete=1    
      ;;    
    ?)    
      error "gh_create_issue(): unknown option"
      ;;    
    esac    
  done    
  shift $((OPTIND - 1));    
    
  test -n "$1" || error "gh_create_issue(): No SHA given"
  #repo can be given as user/repo, /user/repo/, or user/repo/
  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  user="$2"
  repo="$3"
  test -n repo || error "gh_create_issue(): no repo given"
  test -n user || error "gh_create_issue(): no user given"

  # initialize the string
  jstring='{'
  # Get the attributes

  # Milestone
  #if [ -s "$path/milestone" ] ; then
    #milestone=$(fmt "$path/milestone") 
    # jstring="$jstring \"milestone"
  #fi

  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(fmt "$path/assignee")
  # shellcheck disable=SC2089
    jstring="$jstring\"assignee\":\"$(echo "$assignee" | sed 's/ .*//')\","
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    # Remove the open/closed labels
    # shellcheck disable=2089
    # Quotes will be treated literally. Use an array.
    tags='["'$(fmt "$path/tags" | sed 's/ \?\bopen\b \?//' | sed 's/ /","/g')'"]'
    # Process state (open or closed)
    if grep '\bopen\b' >/dev/null < "$path/tags"; then
      jstring="$jstring\"state\":\"open\","
    elif grep '\bclosed\b' > /dev/null; then
      jstring="$jstring\"state\":\"closed\","
    fi
    if [ "$tags" != '[""]' ] ; then
      jstring="$jstring\"labels\":$tags,"
    fi
  fi

  #remove trailing comma and close bracket
  jstring=${jstring%,}'}'
 
  # Description
  # Title is the first line of description
  title=$(head -n 1 "$path/description")
  description=$(tail --lines=+2 < "$path/description")

  # shellcheck disable=SC2090,SC2086
  # jq handles properly escaping the string if passed as variable
  jstring=$(echo $jstring | jq --arg desc "$description" --arg tit "$title" -r '. + {title: $tit, body: $desc}')    #TODO:do same for every

  cd ..
  url="https://api.github.com/repos/$user/$repo/issues"
  gh_api_send "$url" create "$jstring" POST
  num=$(jq '.number' < gh-create-body)
  import_dir="imports/github/$user/$repo/$num"
  cdissues
  test -d "$import_dir" || mkdir -p "$import_dir"
  echo "$isha" > "$import_dir/sha"
  cd ..
  # delete temp files
  test -z $nodelete && rm -f gh-create-body gh-create-header

}

#import issue to temporary directory $TEMP_ISSUE_DIR
gh_import_issue()
{
  local path
  url=$1
  gh_api_get "$url" issue
  path=$(mktemp -d)
  # Create tags (in sorted order to avoid gratuitous updates)
  {
    jq -r ".state" gh-issue-body
    jq -r ".labels[] | .name" gh-issue-body
  } |
    LC_ALL=C sort >"$path/tags" || trans_abort

    # Create assignees (in sorted order to avoid gratuitous updates)
    jq -r ".assignees[] | .login" gh-issue-body |
      LC_ALL=C sort >"$path/assignee" || trans_abort
    # Obtain milestone
    if [ "$(jq ".milestone" gh-issue-body)" = null ] ; then
      if [ -r "$path/milestone" ] ; then
        rm "$path/milestone" || trans_abort
      fi
    else
      jq -r ".milestone.title" gh-issue-body >"$path/milestone" || trans_abort
      git add "$path/milestone" || trans_abort
    fi

    # Create description
    jq -r ".title" gh-issue-body >/dev/null || trans_abort
    jq -r ".body" gh-issue-body >/dev/null || trans_abort
    {
      jq -r ".title" gh-issue-body
      echo
      jq -r ".body" gh-issue-body
    } |
      tr -d \\r >"$path/description"
    TEMP_ISSUE_DIR=$path
    rm -f gh-issue-body gh-issue-header
}
# update a remote GitHub issue, based on a local one
gh_update_issue()
{
  local isha path assignee description url user repo num import_dir
  test -n "$1" || error "gh_update_issue(): No SHA given"
  test -n "$2" || error "gh_update_issue(): No url given"
  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  user="$2"
  repo="$3"
  num="$4"
  test -n repo || error "gh_update_issue(): no repo given"
  test -n user || error "gh_update_issue(): no user given"
  test -n num || error "gh_update_issue(): no num given"
  url="https://api.github.com/repos/$user/$repo/issues/$num"

  gh_import_issue "$url"
  tpath=$TEMP_ISSUE_DIR

  # initialize the string
  jstring='{'

  # Compare the attributes and add the ones that need updating to the jstring

  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(fmt "$path/assignee" | sed 's/ .*//')
    oldassignee=$(fmt "$path/assignee")
    if [ "$assignee" != "$oldassignee" ] ; then
      jstring="$jstring\"assignee\":\"$assignee\","
    fi
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    # sed is used to translate to json
    # and to remove the `open` tag
    tags='["'$(fmt "$path/tags" | sed 's/ \?\bopen\b \?//' | sed 's/ /","/g')'"]'
    oldtags='["'$(fmt "$tpath/tags" | sed 's/ \?\bopen\b \?//' | sed 's/ /","/g')'"]'
    if [ "$tags" != "$oldtags" ] ; then
      # Process state (open or closed)
      if grep '\bopen\b' >/dev/null < "$path/tags"; then
        jstring="$jstring\"state\":\"open\","
        elif grep '\bclosed\b' >/dev/null < "$path/tags"; then
        jstring="$jstring\"state\":\"closed\","
      fi
      if [ "$tags" != '[""]' ] ; then
        jstring="$jstring\"labels\":$tags,"
      fi
    fi
  fi

  #remove trailing comma and close bracket
  jstring=${jstring%,}'}'

  # Description
  # Title is the first line of description
  title=$(head -n 1 "$path/description")
  oldtitle=$(head -n 1 "$tpath/description")
  description=$(tail --lines=+2 < "$path/description")
  olddescription=$(tail --lines=+2 < "$tpath/description")
  # jq handles properly escaping the string if passed as variable
  if [ "$title" != "$oldtitle" ] ; then
    # shellcheck disable=SC2090,SC2086
    jstring=$(echo $jstring | jq --arg title "$title" -r '. + {title: $title}')   #TODO
  fi
  if [ "$title" != "$olddescription" ] ; then
    # shellcheck disable=SC2090,SC2086
    jstring=$(echo $jstring | jq --arg desc "$description" -r '. + {body: $desc}')
  fi
  gh_api_send "$url" update "$jstring" PATCH
  import_dir="imports/github/$user/$repo/$num"
  test -d "$import_dir" || mkdir -p "$import_dir"
  echo "$isha" > "$import_dir/sha"

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

      path=$(issue_path_full "$isha")/comments
      mkdir -p "$path" || trans_abort
      mkdir -p "$import_dir" || trans_abort


      # Add issue import number to allow future updates
      echo "$csha" >"$import_dir/$comment_id"

      # Create comment body
      jq -r ".[$i].body" gh-comments-body >/dev/null || trans_abort
      jq -r ".[$i].body" gh-comments-body |
      tr -d \\r >"$path/$csha"

      git add "$path/$csha" "$import_dir/$comment_id" || trans_abort
      if ! git diff --quiet HEAD ; then
	local name html_url
	name=$(jq -r ".[$i].user.login" gh-comments-body)
	html_url=$(jq -r ".[$i].html_url" gh-comments-body)
	GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-comments-body) \
	  commit 'gi: Import comment message' "gi comment message $isha $csha
Comment URL: $html_url" \
	  --author="$name <$name@users.noreply.github.com>"
	echo "Imported/updated issue #$issue_number comment $comment_id as $(short_sha "$csha")"
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

    path=$(issue_path_full "$sha")
    mkdir -p "$path" || trans_abort
    mkdir -p "$import_dir" || trans_abort

    # Add issue import number to allow future updates
    echo "$sha" >"$import_dir/sha"

    # Create tags (in sorted order to avoid gratuitous updates)
    {
      jq -r ".[$i].state" gh-issue-body
      jq -r ".[$i].labels[] | .name" gh-issue-body
    } |
    LC_ALL=C sort >"$path/tags" || trans_abort

    # Create assignees (in sorted order to avoid gratuitous updates)
    jq -r ".[$i].assignees[] | .login" gh-issue-body |
    LC_ALL=C sort >"$path/assignee" || trans_abort

    if [ -s "$path/assignee" ] ; then
      git add "$path/assignee" || trans_abort
    else
      rm -f "$path/assignee"
    fi

    # Obtain milestone
    if [ "$(jq ".[$i].milestone" gh-issue-body)" = null ] ; then
      if [ -r "$path/milestone" ] ; then
	git rm "$path/milestone" || trans_abort
      fi
    else
      jq -r ".[$i].milestone.title" gh-issue-body >"$path/milestone" || trans_abort
      git add "$path/milestone" || trans_abort
    fi

    # Create description
    jq -r ".[$i].title" gh-issue-body >/dev/null || trans_abort
    jq -r ".[$i].body" gh-issue-body >/dev/null || trans_abort
    {
      jq -r ".[$i].title" gh-issue-body
      echo
      jq -r ".[$i].body" gh-issue-body
    } |
    tr -d \\r >"$path/description"

    git add "$path/description" "$path/tags" imports || trans_abort
    if ! git diff --quiet HEAD ; then
      name=${name:-$(jq -r ".[$i].user.login" gh-issue-body)}
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gh-issue-body) \
	commit "gi: Import issue #$issue_number from GitHub" \
	"Issue URL: https://github.com/$user/$repo/issues/$issue_number" \
	--author="$name <$name@users.noreply.github.com>"
      echo "Imported/updated issue #$issue_number as $(short_sha "$sha")"
    fi

    # Import issue comments
    gh_import_comments "$user" "$repo" "$issue_number" "$sha"
  done
}

gh_export_issues()
{
  local user repo i import_dir sha url

  test "$1" = github -a -n "$2" -a -n "$3" || usage_export
  user="$2"
  repo="$3"

  cdissues
  # For each issue in the respective import dir
  for i in imports/github/"$user/$repo"/[1-9]* ; do
    pwd
    sha=$(cat "$i/sha")
    # extract number
    num=$(echo "$i" | grep -o '[1-9].*$')
    echo "Exporting issue $num"
    url="https://api.github.com/repos/$user/$repo/issues/$num"
    gh_update_issue "$sha" "$user" "$repo" "$num"
    rm -f gh-update-body gh-update-header

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
' gh-"$1"-header
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
  if [ "$begin_sha" != "$(git rev-parse HEAD)" ] ; then
    local checkpoint="imports/github/$user/$repo/checkpoint"
    git rev-parse HEAD >"$checkpoint"
    git add "$checkpoint"
    commit "gi: Import issues from GitHub checkpoint" \
    "Issues URL: https://github.com/$user/$repo/issues"
  fi
}

