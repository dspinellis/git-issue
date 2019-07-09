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
  cat <<\USAGE_export_EOF
gi export usage: git issue export provider user repo
-e        Expand escape attribute sequences before exporting(see gi list -l)

Example: git issue export github torvalds linux
USAGE_export_EOF
  exit 2
}

# Get a page using the GitHub API; abort transaction on error
# Header is saved in the file gh-$prefix-header; body in gh-$prefix-body
gh_api_get()
{
  local url prefix provider

  url="$1"
  prefix="$2"
  provider="$3"

  # figure out the correct authentication token
  if [ "$provider" = github ] ; then
    authtoken="$GI_CURL_AUTH"
  elif [ "$provider" = gitlab ] ; then
    authtoken="$GL_CURL_AUTH"
  else
    trans_abort
  fi

  if ! curl -H "$authtoken" -A "$USER_AGENT" -s \
    -o "gh-$prefix-body" -D "gh-$prefix-header" "$url" ; then
    echo 'GitHub connection failed' 1>&2
    trans_abort
  fi

  if ! grep -q '^\(Status: 200\|HTTP/1.1 200 OK\)' "gh-$prefix-header" ; then
    echo "$provider API communication failure" 1>&2
    echo "URL: $url" 1>&2
    if grep -q '^Status: 4' "gh-$prefix-header" ; then
      jq -r '.message' "gh-$prefix-body" 1>&2
    fi
    trans_abort
  fi
}

# POST, PATCH, PUT or DELETE data using the GitHub API; abort transaction on error
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
  elif [ "$mode" = 'DELETE' ] ; then
    curl_mode='--request DELETE'
  elif [ "$mode" = 'POST' ] ; then
    curl_mode=''
  else
    error "incorrect gh_api_send() mode: $mode"
  fi

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
# gh_create_issue: export issues to GitHub {{{1
usage_create_issue()
{
  cat <<\USAGE_create_issue_EOF
gi create usage: git issue create id provider user repo
-e        Expand escape attribute sequences before exporting(see gi list -l)

Example: git issue create id github torvalds linux
USAGE_create_issue_EOF
  exit 2
}


# Create an issue in Github, based on a local one
gh_create_issue()
{
  local isha path assignee description url user repo nodelete OPTIND
     
  while getopts neu: flag ; do    
    case $flag in    
    n)    
      nodelete=1    
      ;;    
    u)
      num=$OPTARG
      ;;
    e)
      attr_expand=1    
      ;;
    ?)    
      error "gh_create_issue(): unknown option"
      ;;    
    esac    
  done    
  shift $((OPTIND - 1));    
    
  test -n "$1" || error "gh_create_issue(): No SHA given"
  test -n "$2" || error "gh_create_issue(): no repo given"
  test -n "$3" || error "gh_create_issue(): no user given"
  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  user="$2"
  repo="$3"

  # initialize the string
  jstring='{}'
  # Get the attributes
  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(fmt "$path/assignee")
    jstring=$(echo "$jstring" | jq --arg A "$assignee" -r '. + { assignee: $A }')
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    # format tags as json array
    tags=$(head "$path/tags" | jq --slurp --raw-input 'split("\n")')
    # Process state (open or closed)
    if grep '\bopen\b' >/dev/null < "$path/tags"; then
      jstring=$(echo "$jstring" | jq -r '. + { state: "open" }')
    elif grep '\bclosed\b' > /dev/null; then
      jstring=$(echo "$jstring" | jq -r '. + { state: "closed" }')
    fi
    tags=$(echo "$tags" | jq 'map(select(. != "open"))')
    tags=$(echo "$tags" | jq 'map(select(. != "closed"))')
    tags=$(echo "$tags" | jq 'map(select(. != ""))')
    if [ "$tags" != '[]' ] ; then
      jstring=$(echo "$jstring" | jq -r ". + { labels: $tags }")
    fi
  fi

 # Description
  # Title is the first line of description
  title=$(head -n 1 "$path/description")
  description=$(tail --lines=+3 < "$path/description")

  # Handle formatting indicators
  if [ -n "$attr_expand" ] ; then
    description=$(shortshow "$path" "$description" 'i' "$isha" | sed 's/^.*\x02//' | tr '\001' '\n')
  fi

  # jq handles properly escaping the string if passed as variable
  jstring=$(echo "$jstring" | jq --arg desc "$description" --arg tit "$title" -r '. + {title: $tit, body: $desc}')

 # Milestone

  if [ -s "$path/milestone" ] ; then

    milestone=$(fmt "$path/milestone")
    # Milestones are separate entities in the GitHub API
    # They need to be created before use on an issue
    # get milestone list
    gh_api_get "https://api.github.com/repos/$user/$repo/milestones" milestone github

    for i in $(seq 0 $(($(jq '. | length' gh-milestone-body) - 1)) ) ; do
      milenum=$(jq -r ".[$i].number" gh-milestone-body)
      miletitle=$(jq -r ".[$i].title" gh-milestone-body)
      if [ "$miletitle" = "$milestone" ] ; then
        # it already exists
        found=$milenum
      fi
    done

    if ! [[ "$found" ]] ; then
      # we need to create it
        gh_api_send "https://api.github.com/repos/$user/$repo/milestones" mileres "{ \"title\": \"$milestone\",
        \"state\": \"open\", \"description\":\"\"}" POST
        found=$(jq '.number' gh-mileres-body)
      fi
      jstring=$(echo "$jstring" | jq --arg A "$found" -r '. + { milestone: $A }')

    fi
 
  cd ..
  if [ -n "$num" ] ; then
    url="https://api.github.com/repos/$user/$repo/issues/$num"
    gh_api_send "$url" update "$jstring" PATCH
  else
    url="https://api.github.com/repos/$user/$repo/issues"
    gh_api_send "$url" create "$jstring" POST
    num=$(jq '.number' < gh-create-body)
  fi
  import_dir="imports/github/$user/$repo/$num"

  cdissues
  test -d "$import_dir" || mkdir -p "$import_dir"
  echo "$isha" > "$import_dir/sha"
  git add "$import_dir"
  commit "gi: Add $import_dir" 'gi new mark'
  cd ..
  # delete temp files
  test -z $nodelete && rm -f gh-create-body gh-create-header
  rm -f gh-milestone-body gh-milestone-header
  # dont inherit `test` exit status
  cdissues
}

#import issue to temporary directory $TEMP_ISSUE_DIR
gh_import_issue()
{
  local path
  url=$1
  gh_api_get "$url" issue github
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
  test -n "$2" || error "gh_update_issue(): No URL given"
  test -n "$3" || error "gh_update_issue(): No repo given"
  test -n "$4" || error "gh_update_issue(): No num given"
  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  user="$2"
  repo="$3"
  num="$4"
  url="https://api.github.com/repos/$user/$repo/issues/$num"

  gh_import_issue "$url"
  tpath=$TEMP_ISSUE_DIR

  # initialize the string
  jstring='{}'

  # Compare the attributes and add the ones that need updating to the jstring

  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(fmt "$path/assignee" | sed 's/ .*//')
    oldassignee=$(fmt "$tpath/assignee")
    if [ "$assignee" != "$oldassignee" ] ; then
      jstring=$(echo "$jstring" | jq --arg A "$assignee" -r '. + { assignee: $A }')
    fi
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    tags=$(fmt "$path/tags" | tr -d '\n' | jq --slurp --raw-input 'split(" ")')
    oldtags=$(fmt "$tpath/tags" | tr -d '\n' | jq --slurp --raw-input 'split(" ")')
    tags=$(echo "$tags" | jq 'map(select(. != "open"))')
    tags=$(echo "$tags" | jq 'map(select(. != "closed"))')
    oldtags=$(echo "$oldtags" | jq 'map(select(. != "open"))')
    oldtags=$(echo "$oldtags" | jq 'map(select(. != "closed"))')
    if [ "$tags" != "$oldtags" ] ; then
      # Process state (open or closed)
      if grep '\bopen\b' >/dev/null < "$path/tags"; then
        jstring=$(echo "$jstring" | jq -r '. + { state: "open" }')
      elif grep '\bclosed\b' > /dev/null; then
        jstring=$(echo "$jstring" | jq -r '. + { state: "closed" }')
      fi
      if [ "$tags" != '[]' ] ; then
        jstring=$(echo "$jstring" | jq -r ". + { labels: $tags }")
      fi
    fi
  fi

  # Milestone

  if [ -s "$path/milestone" ] ; then

    milestone=$(fmt "$path/milestone")
    oldmilestone=$(fmt "$tpath/milestone" 2> /dev/null)
    if [ "$milestone" != "$oldmilestone" ] ; then

      # Milestones are separate entities in the GitHub API
      # They need to be created before use on an issue
      # get milestone list
      gh_api_get "https://api.github.com/repos/$user/$repo/milestones" milestone

      for i in $(seq 0 $(($(jq '. | length' gh-milestone-body) - 1)) ) ; do
        milenum=$(jq -r ".[$i].number" gh-milestone-body)
        miletitle=$(jq -r ".[$i].title" gh-milestone-body)
        if [ "$miletitle" = "$milestone" ] ; then
          # it already exists
          found=$milenum
        fi
      done

      if ! [[ "$found" ]] ; then
        # we need to create it
        gh_api_send "https://api.github.com/repos/$user/$repo/milestones" mileres "{ \"title\": \"$milestone\",
        \"state\": \"open\", \"description\":\"\"}" POST
        found=$(jq '.number' gh-mileres-body)
      fi
      jstring=$(echo "$jstring" | jq --arg A "$found" -r '. + { milestone: $A }')

    fi
  fi
 
  # Description
  # Title is the first line of description
  title=$(head -n 1 "$path/description")
  oldtitle=$(head -n 1 "$tpath/description")
  description=$(tail --lines=+3 < "$path/description")
  # Handle formatting indicators
  if [ -n "$attr_expand" ] ; then
    description=$(shortshow "$path" "$description" 'i' "$isha" | sed 's/^.*\x02//' | tr '\001' '\n')
  fi
  olddescription=$(tail --lines=+3 < "$tpath/description")
  # Handle formatting indicators
  olddescription=$(shortshow "$tpath" "$olddescription" 'i' "$isha" | sed 's/^.*\x02//' | tr '\001' '\n')

  # jq handles properly escaping the string if passed as variable
  if [ "$title" != "$oldtitle" ] ; then
    jstring=$(echo "$jstring" | jq --arg title "$title" -r '. + {title: $title}')
  fi
  if [ "$description" != "$olddescription" ] ; then
    jstring=$(echo "$jstring" | jq --arg desc "$description" -r '. + {body: $desc}')
  fi
  if [ "$jstring" != '{}' ] ; then
    gh_api_send "$url" update "$jstring" PATCH
  fi
  import_dir="imports/github/$user/$repo/$num"
  test -d "$import_dir" || mkdir -p "$import_dir"
  echo "$isha" > "$import_dir/sha"
  git add "$import_dir"
  commit "gi: Add $import_dir" 'gi new mark'

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
    gh_api_get "$endpoint" comments github

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

gl_import_issues()
{
  local user repo
  local i issue_number import_dir sha path name desc milestone assignee

  user="$1"
  repo="$2"
  endpoint="https://gitlab.com/api/v4/projects/$user%2F$repo/issues"

  cdissues
  curl -s -H "$GL_CURL_AUTH" -A "$USER_AGENT" -o gl-issue-body "$endpoint"
  # For each issue in the gh-issue-body file
  for i in $(seq 0 $(($(jq '. | length' gl-issue-body) - 1)) ) ; do
    issue_number=$(jq ".[$i].iid" gl-issue-body)

    # See if issue already there
    import_dir="imports/gitlab/$user/$repo/$issue_number"
    if [ -d "$import_dir" ] ; then
      sha=$(cat "$import_dir/sha")
    else
      name=$(jq -r ".[$i].author.username" gl-issue-body)
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gl-issue-body) \
      commit 'gi: Add issue' 'gi new mark' \
	--author="$name <$name@users.noreply.gitlab.com>"
      sha=$(git rev-parse HEAD)
    fi

    path=$(issue_path_full "$sha")
    mkdir -p "$path" || trans_abort
    mkdir -p "$import_dir" || trans_abort

    # Add issue import number to allow future updates
    echo "$sha" >"$import_dir/sha"

    # Create tags (in sorted order to avoid gratuitous updates)
    {
      # convert to our format
      jq -r ".[$i].state" gl-issue-body | sed 's/opened/open/'
      jq -r ".[$i].labels[]" gl-issue-body
    } |
    LC_ALL=C sort >"$path/tags" || trans_abort

    # Create assignees (in sorted order to avoid gratuitous updates)
    jq -r ".[$i].assignees[] | .username" gl-issue-body |
    LC_ALL=C sort >"$path/assignee" || trans_abort

    if [ -s "$path/assignee" ] ; then
      git add "$path/assignee" || trans_abort
    else
      rm -f "$path/assignee"
    fi

    # Obtain milestone
    if [ "$(jq ".[$i].milestone" gl-issue-body)" = null ] ; then
      if [ -r "$path/milestone" ] ; then
	git rm "$path/milestone" || trans_abort
      fi
    else
      jq -r ".[$i].milestone.title" gl-issue-body >"$path/milestone" || trans_abort
      git add "$path/milestone" || trans_abort
    fi

    # Due Date
    duedate=$(jq -r ".[$i].due_date" gl-issue-body)
    if [ "$duedate" = null ] ; then
      if [ -r "$path/duedate" ] ; then
	git rm "$path/duedate" || trans_abort
      fi
    else
      # convert duedate to our format before saving
      $DATEBIN --date="$duedate" --iso-8601=seconds >"$path/duedate" || trans_abort
      git add "$path/duedate" || trans_abort
    fi

    # Timespent
    timespent=$(jq -r ".[$i].time_stats.total_time_spent" gl-issue-body)
    if [ "$timespent" = '0' ] ; then
      if [ -r "$path/timespent" ] ; then
	git rm "$path/timespent" || trans_abort
      fi
    else
      echo "$timespent" >"$path/timespent" || trans_abort
      git add "$path/timespent" || trans_abort
    fi

    # Timeestimate
    timeestimate=$(jq -r ".[$i].time_stats.time_estimate" gl-issue-body)
    if [ "$timeestimate" = '0' ] ; then
      if [ -r "$path/timeestimate" ] ; then
	git rm "$path/timeestimate" || trans_abort
      fi
    else
      echo "$timeestimate" >"$path/timeestimate" || trans_abort
      git add "$path/timeestimate" || trans_abort
    fi

    # Weight
    weight=$(jq -r ".[$i].weight" gl-issue-body)
    if [ "$weight" = 'null' ] ; then
      if [ -r "$path/weight" ] ; then
        git rm "$path/weight" || trans_abort
      fi
    else
      echo "$weight" > "$path/weight" || trans_abort
      git add "$path/weight" || trans_abort
    fi

    # Create description
    jq -r ".[$i].title" gl-issue-body >/dev/null || trans_abort
    desc=$(jq -r ".[$i].description" gl-issue-body) 
    if [ "$desc" = "null" ] ; then
      #no description
      desc="";
    fi
    {
      jq -r ".[$i].title" gl-issue-body
      echo
      echo "$desc"
    } |
    tr -d \\r >"$path/description"

    git add "$path/description" "$path/tags" imports || trans_abort
    if ! git diff --quiet HEAD ; then
      name=${name:-$(jq -r ".[$i].user.login" gl-issue-body)}
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" gl-issue-body) \
	commit "gi: Import issue #$issue_number from GitHub" \
	"Issue URL: https://gitlab.com/$user/$repo/issues/$issue_number" \
	--author="$name <$name@users.noreply.github.com>"
      echo "Imported/updated issue #$issue_number as $(short_sha "$sha")"
    fi

    #TODO comments
  done
  rm -f gl-issue-body
}

gh_export_issues()
{
  local user repo i import_dir sha url

  while getopts e flag ; do    
    case $flag in    
    e)    
      # global flag to enable escape sequence 
      attr_expand=1    
      ;;    
    ?)    
      error "gl_export_issues(): unknown option"
      ;;    
    esac    
  done    
  shift $((OPTIND - 1));    
 
  test "$1" = github -a -n "$2" -a -n "$3" || usage_export
  user="$2"
  repo="$3"

  cdissues
  test -d imports/github/"$user/$repo" || error "No local issues found for this repository."

  # For each issue in the respective import dir
  for i in imports/github/"$user/$repo"/[1-9]* ; do
    sha=$(cat "$i/sha")
    # extract number
    num=$(echo "$i" | grep -o '/[1-9].*$' | tr -d '/')
    echo "Exporting issue $sha as #$num"
    url="https://api.github.com/repos/$user/$repo/issues/$num"
    gh_create_issue -u "$num" "$sha" "$user" "$repo"
    rm -f gh-create-body gh-create-header

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
  local endpoint user repo begin_sha provider

  test "$1" = github -o "$1" = gitlab -a -n "$2" -a -n "$3" || usage_import
  provider="$1"
  user="$2"
  repo="$3"

  cdissues

  prerequisite_command jq
  prerequisite_command curl

  begin_sha=$(git rev-parse HEAD)

  mkdir -p "imports/$provider/$user/$repo"
  # Process GitHub issues page by page
  trans_start
    if [ "$provider" = github ] ; then
      endpoint="https://api.github.com/repos/$user/$repo/issues?state=all"
    else
      endpoint="https://gitlab.com/api/v4/projects/$user%2F$repo/issues"
    fi
  while true ; do
    gh_api_get "$endpoint" issue "$provider"
    if [ "$provider" = github ] ; then
      gh_import_issues "$user" "$repo"
    else
      gl_import_issues "$user" "$repo"
    fi

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
    local checkpoint="imports/$provider/$user/$repo/checkpoint"
    git rev-parse HEAD >"$checkpoint"
    git add "$checkpoint"
    commit "gi: Import issues from GitHub checkpoint" \
    "Issues URL: https://$provider.com/$user/$repo/issues"
  fi
}
