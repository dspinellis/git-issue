#!/bin/sh
# shellcheck disable=2039
# SC2039: In POSIX sh, 'local' is undefined

# import: import issues from GitHub/GitLab {{{1
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


# Escape special URL characters in argument string using Percent-encoding
urlescape()
{
  echo "$1" |
  sed 's.%.%25.' |
  sed -e 's./.%2F.' \
  -e 's.!.%21.' \
  -e 's.#.%23.' \
  -e 's.\$.%24.' \
  -e 's.&.%26.' \
  -e 's.'\''.%27.' \
  -e 's.(.%28.' \
  -e 's.).%29.' \
  -e 's.*.%2A.' \
  -e 's.+.%2B.' \
  -e 's.,.%2C.' \
  -e 's.:.%3A.' \
  -e 's.;.%3B.'

}
# Get a page using the GitHub/GitLab API; abort transaction on error
# Header is saved in the file $prefix-header; body in $prefix-body
rest_api_get()
{
  local url prefix provider authtoken

  url="$1"
  prefix="$2"
  provider="$3"

  # use the correct authentication token
  if [ "$provider" = github ] ; then
    authtoken="$GI_CURL_AUTH"
  elif [ "$provider" = gitlab ] ; then
    authtoken="$GL_CURL_AUTH"
  else
    trans_abort
  fi

  if ! curl -H "$authtoken" -A "$USER_AGENT" -s \
    -o "$prefix-body" -D "$prefix-header" "$url" ; then
    echo "$provider connection failed" 1>&2
    trans_abort
  fi

  if ! grep -q '^\(Status: 200\|HTTP/[[:digit:]].[[:digit:]] 200 OK\)' "$prefix-header" ; then
    echo "$provider API communication failure" 1>&2
    echo "URL: $url" 1>&2
    if grep -q '^\(Status: 4\|HTTP/[0-9].[0-9] 4\)' "$prefix-header" ; then
      jq -r '.message' "$prefix-body" 1>&2
    fi
    trans_abort
  fi
}

# POST, PATCH, PUT or DELETE data using the GitHub API; abort transaction on error
# Header is saved in the file $prefix-header; body in $prefix-body

rest_api_send()
{
  local url prefix data mode curl_mode authtoken

  url="$1"
  prefix="$2"
  data="$3"
  mode=${4:-"POST"}
  provider="$5"
  if [ "$mode" = 'PATCH' ] ; then
    curl_mode='--request PATCH'
  elif [ "$mode" = 'PUT' ] ; then
    curl_mode='--request PUT'
  elif [ "$mode" = 'DELETE' ] ; then
    curl_mode='--request DELETE'
  elif [ "$mode" = 'POST' ] ; then
    curl_mode=''
  else
    error "incorrect rest_api_send() mode: $mode"
  fi

  # use the correct authentication token
  if [ "$provider" = github ] ; then
    authtoken="$GI_CURL_AUTH"
  elif [ "$provider" = gitlab ] ; then
    authtoken="$GL_CURL_AUTH"
  else
    trans_abort
  fi

  if ! curl --header "Content-Type: application/json" -H "$authtoken" -A "$USER_AGENT" -s \
    -o "$prefix-body" -D "$prefix-header" $curl_mode --data "$data" "$url" ; then
    echo 'GitHub connection failed' 1>&2
    trans_abort
  fi

  if ! grep -q '^\(Status: 20[0-9]\|HTTP/[[:digit:]].[[:digit:]] 20[1-9] Created\|HTTP/[[:digit:]].[[:digit:]] 200 OK\)' "$prefix-header" ; then
    echo 'GitHub API communication failure' 1>&2
    echo "URL: $url" 1>&2
    echo "Data: $data" 1>&2
    if grep -q '^\(Status: 4\|HTTP/[0-9].[0-9] 4\)' "$prefix-header" ; then
      jq -r '.message' "$prefix-body" 1>&2
    fi
    trans_abort
  fi
}
# create_issue: export issues to GitHub {{{1
usage_create_issue()
{
  cat <<\USAGE_create_issue_EOF
gi create usage: git issue create id provider user repo
-e        Expand escape attribute sequences before exporting(see gi list -l)
-n        Keep HTTP transaction files 
-u num    Update issue #num instead of creating a new one

Example: git issue create 0123 github torvalds linux
USAGE_create_issue_EOF
  exit 2
}


# Create an issue in GitHub/GitLab, based on a local one
create_issue()
{
  local isha path assignee tags title description url provider user repo 
  local nodelete OPTIND escrepo update num import_dir attr_expand jstring
     
  while getopts neu: flag ; do    
    case $flag in    
    n)    
      nodelete=1    
      ;;    
    u)
      num=$OPTARG
      update=1
      ;;
    e)
      attr_expand=1    
      ;;
    ?)    
      usage_create_issue
      ;;    
    esac    
  done    
  shift $((OPTIND - 1));    
    
  test -n "$1" || usage_create_issue
  test "$2" = github -o "$2" = gitlab || usage_create_issue
  test -n "$3" || usage_create_issue
  test -n "$4" || usage_create_issue
  cdissues
  path=$(issue_path_part "$1") || exit
  isha=$(issue_sha "$path")
  provider="$2"
  user="$3"
  repo="$4"

  if [ "$provider" = gitlab ] ; then
    # if the repo belongs to a group, repo will be in the format groupname/reponame
    # we need to escape the / for URLs
    escrepo=$(urlescape "$repo")
  fi
  # initialize the string
  jstring='{}'
  # Get the attributes
  # Assignee
  if [ -r "$path/assignee" ] ; then
    assignee=$(fmt "$path/assignee")
    if [ "$provider" = github ] ; then
      jstring=$(echo "$jstring" | jq --arg A "$assignee" -r '. + { assignee: $A }')
    else
      rest_api_get "https://gitlab.com/api/v4/users?username=$assignee" assignee gitlab
      if [ "$(fmt assignee-body)" = '[]' ] ; then
        echo "Couldn't find assignee in GitLab, skipping assignment."
      else
        jstring=$(echo "$jstring" | jq -r ". + { assignee_ids: [$(jq -r '.[0].id' assignee-body)]}")
      fi
    fi
  fi

  # Tags
  if [ -s "$path/tags" ] ; then
    # format tags as json array
    tags=$(head "$path/tags" | jq --slurp --raw-input 'split("\n")')
    # Process state (open--opened-- or closed)
    if [ -n "$num" ] ; then
      if grep '^open$' >/dev/null < "$path/tags"; then
        if [ "$provider" = github ] ; then
          jstring=$(echo "$jstring" | jq -r '. + { state: "open" }')
        else
          jstring=$(echo "$jstring" | jq -r '. + { state_event: "reopen" }')
        fi
      else
        if [ "$provider" = gitlab ] ; then
          jstring=$(echo "$jstring" | jq -r '. + { state_event: "close" }')
        else
          jstring=$(echo "$jstring" | jq -r '. + { state: "closed" }')
        fi
      fi
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
  description=$(tail --lines=+3 "$path/description" | head -c -1 ; echo x)

  # Handle formatting indicators
  if [ -n "$attr_expand" ] ; then
    title=$(shortshow "$path" "$title" 'i' "$isha" | sed 's/^.*\x02//' | tr '\001' '\n')
    description=$(shortshow "$path" "$description" 'i' "$isha" | sed 's/^.*\x02//' | tr '\001' '\n')
    # update description
    {
      echo "$title"
      echo
      echo "$description"
    } >"$path/description"
    git add "$path/description" || trans_abort
    if ! git diff --quiet HEAD ; then
      commit "gi: expand attributes in description of issue $isha" "gi description attribute expand $isha"
    fi
  fi

  # jq handles properly escaping the string if passed as variable
  if [ "$provider" = github ] ; then
    jstring=$(echo "$jstring" | jq --arg desc "${description%x}" --arg tit "$title" -r '. + {title: $tit, body: $desc}')
  else
    # add trailing spaces if needed, or gitlab will ignore the newline
    description=$(echo "$description" | sed '$!s/[^ ] \?$/&  /')
    jstring=$(echo "$jstring" | jq --arg desc "${description%x}" --arg tit "$title" -r '. + {title: $tit, description: $desc}')
  fi

  # Due Date (not supported on github)
  if [ -s "$path/duedate" ] && [ "$provider" = gitlab ] ; then
    local duedate
    # gitlab date must be in YYYY-MM-DD format
    duedate=$($DATEBIN --iso-8601 --date="$(fmt "$path/duedate")")
    jstring=$(echo "$jstring" | jq --arg D "$duedate" -r '. + { due_date: $D }')
  fi

  # Weight (only supported on gitlab starter+)
  if [ -s "$path/weight" ] && [ "$provider" = gitlab ] ; then
    local weight
    weight=$(fmt "$path/weight")
    jstring=$(echo "$jstring" | jq --arg W "$weight" -r '. + { weight: $W }')
  fi

  # Milestone
  if [ -s "$path/milestone" ] ; then
    local mileurl jmileid milestone milenum miletitle found
    milestone=$(fmt "$path/milestone")
    # Milestones are separate entities in the GitHub and GitLab API
    # They need to be created before use on an issue
    if [ "$provider" = github ] ; then
      mileurl="https://api.github.com/repos/$user/$repo/milestones"
      jmileid='number'
    else
      mileurl="https://gitlab.com/api/v4/projects/$user%2F$escrepo/milestones"
      jmileid='id'
    fi
    # get milestone list
    rest_api_get "$mileurl" milestone "$provider"

    for i in $(seq 0 $(($(jq '. | length' milestone-body) - 1)) ) ; do
      milenum=$(jq -r ".[$i].$jmileid" milestone-body)
      miletitle=$(jq -r ".[$i].title" milestone-body)
      if [ "$miletitle" = "$milestone" ] ; then
        # it already exists
        found=$milenum
        break
      fi
    done

    if ! [[ "$found" ]] ; then
      # we need to create it
      echo "Creating new Milestone $milestone..."
      rest_api_send "$mileurl" mileres "{ \"title\": \"$milestone\",
      \"state\": \"open\", \"description\":\"\"}" POST "$provider"
      found=$(jq ".$jmileid" mileres-body)
    fi
    if [ "$provider" = github ] ; then
      jstring=$(echo "$jstring" | jq --arg A "$found" -r '. + { milestone: $A }')
    else
      jstring=$(echo "$jstring" | jq --arg A "$found" -r '. + { milestone_id: $A }')
    fi
  fi
 
  cd ..
  if [ -n "$num" ] ; then
    if [ "$provider" = github ] ; then
      url="https://api.github.com/repos/$user/$repo/issues/$num"
      rest_api_send "$url" update "$jstring" PATCH github
    else
      url="https://gitlab.com/api/v4/projects/$user%2F$escrepo/issues/$num"
      rest_api_send "$url" update "$jstring" PUT gitlab
    fi
  else
    # Check if issue already exists
    for i in ".issues/imports/$provider/$user/$repo"/[1-9]* ; do
      local sha
      sha=$(cat "$i/sha" 2> /dev/null)
      if [ "$sha" = "$isha" ] ; then
        local num
        num=$(echo "$i" | grep -o '/[1-9].*$' | tr -d '/')
        error "Error: Local issue $sha is linked with $provider issue #$num.Cannot create duplicate."
      fi
    done

    if [ "$provider" = github ] ; then
      url="https://api.github.com/repos/$user/$repo/issues"
    else
      url="https://gitlab.com/api/v4/projects/$user%2F$escrepo/issues"
    fi
    rest_api_send "$url" create "$jstring" POST "$provider"
    if [ "$provider" = github ] ; then
      num=$(jq '.number' create-body)
      url="https://api.github.com/repos/$user/$repo/issues/$num"
    else
      num=$(jq '.iid' create-body)
      # update url to that of created issue
      url="https://gitlab.com/api/v4/projects/$user%2F$escrepo/issues/$num"
    fi
  fi
  import_dir="imports/$provider/$user/$repo/$num"

  # Time estimate/time spent

  cdissues
  local timeestimate timespent
  if [ -s "$path/timeestimate" ] && [ "$provider" = gitlab ] ; then
    timeestimate=$(fmt "$path/timeestimate")
    echo "Adding Time Estimate..."
    rest_api_send "$url/time_estimate?duration=${timeestimate}s" timeestimate "" POST gitlab
  fi

  if [ -s "$path/timespent" ] && [ "$provider" = gitlab ] ; then
    timespent=$(fmt "$path/timespent")
    if [ -n "$num" ] ; then
      local oldspent
      # get existing timestats
      rest_api_get "$url/time_stats" timestats gitlab
      oldspent=$(jq -r '.total_time_spent' timestats-body)
      if [ "$oldspent" -lt "$timespent" ] ; then
        echo "Adding Time Spent..."
        rest_api_send "$url/add_spent_time?duration=$((timespent - oldspent))s" timespent "" POST gitlab
      elif [ "$oldspent" -gt "$timespent" ] ; then
        # we need to reset time first
        echo "Local Time Spent less than remote. Resetting and adding Time Spent..."
        rest_api_send "$url/reset_spent_time" timespent "" POST gitlab
        rest_api_send "$url/add_spent_time?duration=${timespent}s" timespent "" POST gitlab
      fi
    else
        rest_api_send "$url/add_spent_time?duration=${timespent}s" timespent "" POST gitlab
    fi
  fi

  # Update issue state if we create a closed issue
  if grep -q '^closed$' "$path/tags" && [ -z "$update" ] ; then
    if [ "$provider" = github ] ; then
      rest_api_send "$url" update "{ \"state\": \"closed\" }" PATCH github
    else
      rest_api_send "$url" update "{ \"state_event\": \"close\" }" PUT gitlab
    fi
  fi

  test -d "$import_dir" || mkdir -p "$import_dir"
  echo "$isha" > "$import_dir/sha"
  git add "$import_dir"
  commit "gi: Add $import_dir" 'gi new mark'

  # Comments
  if [ -d "$path/comments" ] ; then

    local csha
    git log --reverse --grep="^gi comment mark $isha" --format='%H' |
    while read -r csha ; do
      local cbody cfound cjstring
      cbody=$(sed '$!s/[^ ] \?$/&  /' "$path/comments/$csha" | head -c -1 ; echo x)
      cfound=
      for j in "$import_dir"/comments/* ; do
        if [ "$(cat "$j" 2> /dev/null)" = "$csha" ] ; then
          cfound=$(echo "$j" | sed 's:.*comments/\(.*\)$:\1:')
          break
        fi
      done
      cjstring=$(echo '{}' | jq --arg desc "${cbody%x}" '{body: $desc}')
      if [ -n "$cfound" ] ; then
        # the comment exists already
        echo "Updating comment $csha..."
        if [ "$provider" = github ] ; then
          rest_api_send "https://api.github.com/repos/$user/$repo/issues/comments/$cfound" commentupdate "$cjstring" PATCH github
        else
          rest_api_send "$url/notes/$cfound" commentupdate "$cjstring" PUT gitlab
        fi
      else
        # we need to create it
        echo "Creating comment $csha..."
        if [ "$provider" = github ] ; then
          rest_api_send "$url/comments" commentcreate "$cjstring" POST github
        else
          rest_api_send "$url/notes" commentcreate "$cjstring" POST gitlab
        fi
        test -d "$import_dir/comments" || mkdir -p "$import_dir/comments"
        echo "$csha" > "$import_dir/comments/$(jq -r '.id' commentcreate-body)"
      fi
    done
  fi

  # delete temp files
  test -z $nodelete && rm -f ../create-body ../create-header
  rm -f milestone-body milestone-header mileres-body mileres-header
  rm -f timeestimate-body timeestimate-header timespent-body timespent-header timestats-body timestats-header
  rm -f commentupdate-header commentupdate-body commentcreate-header commentcreate-body
}

# Import GitHub/GitLab comments for the specified issue
# import_comments <user> <repo> <issue_number> <issue_sha> <provider>
import_comments()
{
  local user repo issue_number isha
  local i endpoint comment_id import_dir csha provider juser

  user="$1"
  shift
  repo="$1"
  shift
  issue_number="$1"
  shift
  isha="$1"
  shift
  provider="$1"
  shift

  if [ "$provider" = github ] ; then
    endpoint="https://api.github.com/repos/$user/$repo/issues/$issue_number/comments"
    juser='user.login'
  elif [ "$provider" = gitlab ] ; then
    # if $repo contains '/' then it's part of a group and needs to be escaped
    local escrepo
    escrepo=$(urlescape "$repo")
    endpoint="https://gitlab.com/api/v4/projects/$user%2F$escrepo/issues/$issue_number/notes"
    juser='author.username'
  else
    trans_abort
  fi

  while true ; do
    rest_api_get "$endpoint" comments "$provider"

    # For each comment in the comments-body file
    for i in $(seq 0 $(($(jq '. | length' comments-body) - 1)) ) ; do
      # Dont import automated system comments
      test ! "$(jq -r ".[$i].system" comments-body)" = true || continue
      comment_id=$(jq -r ".[$i].id" comments-body)

      # See if comment already there
      import_dir="imports/$provider/$user/$repo/$issue_number/comments"
      if [ -r "$import_dir/$comment_id" ] ; then
	csha=$(cat "$import_dir/$comment_id")
      else
	name=$(jq -r ".[$i].$juser" comments-body)
	GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" comments-body) \
	  commit 'gi: Add comment' "gi comment mark $isha" \
	  --author="$name <$name@users.noreply.$provider.com>"
	csha=$(git rev-parse HEAD)
      fi

      path=$(issue_path_full "$isha")/comments
      mkdir -p "$path" || trans_abort
      mkdir -p "$import_dir" || trans_abort


      # Add issue import number to allow future updates
      echo "$csha" >"$import_dir/$comment_id"

      # Create comment body
      jq -r ".[$i].body" comments-body >/dev/null || trans_abort
      jq -r ".[$i].body" comments-body |
      tr -d \\r >"$path/$csha"

      git add "$path/$csha" "$import_dir/$comment_id" || trans_abort
      if ! git diff --quiet HEAD ; then
	local name html_url
        name=$(jq -r ".[$i].$juser" comments-body)
        if [ "$provider" = github ] ; then
          html_url=$(jq -r ".[$i].html_url" comments-body)
          GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" comments-body) \
	    commit 'gi: Import comment message' "gi comment message $isha $csha
Comment URL: $html_url" \
	    --author="$name <$name@users.noreply.github.com>"
        else
          GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" comments-body) \
	    commit 'gi: Import comment message' "gi comment message $isha $csha"\
	    --author="$name <$name@users.noreply.gitlab.com>"
        fi

	echo "Imported/updated issue #$issue_number comment $comment_id as $(short_sha "$csha")"
      fi
    done # For all comments on page

    # Return if no more pages
    if ! grep -q '^Link:.*rel="next"' comments-header ; then
      break
    fi

    # Move to next point
    endpoint=$(rest_next_page_url comments)
  done
}

# Import GitHub or GitLab issues stored in the file issue-body as JSON data
# import_issues user repo provider
import_issues()
{
  local user repo provider
  local i issue_number import_dir sha path name
  local duedate timeestimate timespent weight
  local jid juser jlogin jdesc


  user="$1"
  repo="$2"
  provider="$3"

  # some json field names differ
  if [ "$provider" = github ] ; then
    jid='number'
    juser='user.login'
    jlogin='login'
    jdesc='body'
  elif [ "$provider" = gitlab ] ; then
    jid='iid'
    juser='author.username'
    jlogin='username'
    jdesc='description'
  else
    trans_abort
  fi

  # For each issue in the issue-body file
  for i in $(seq 0 $(($(jq '. | length' issue-body) - 1)) ) ; do
    issue_number=$(jq -r ".[$i].$jid" issue-body)

    # See if issue already there
    import_dir="imports/$provider/$user/$repo/$issue_number"
    if [ -d "$import_dir" ] ; then
      sha=$(cat "$import_dir/sha")
    else
      name=$(jq -r ".[$i].$juser" issue-body)
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" issue-body) \
      commit 'gi: Add issue' 'gi new mark' \
	--author="$name <$name@users.noreply.$provider.com>"
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
      jq -r ".[$i].state" issue-body | sed 's/opened/open/'
      if [ "$provider" = github ] ; then
        jq -r ".[$i].labels[] | .name" issue-body
      else
        jq -r ".[$i].labels[]" issue-body
      fi
    } |
    LC_ALL=C sort >"$path/tags" || trans_abort

    # Create assignees (in sorted order to avoid gratuitous updates)
    if [ "$(jq -r ".[$i].assignees | length" issue-body)" != 0 ] ; then
      jq -r ".[$i].assignees[] | .$jlogin" issue-body |
      LC_ALL=C sort >"$path/assignee" || trans_abort
    fi

    if [ -s "$path/assignee" ] ; then
      git add "$path/assignee" || trans_abort
    else
      rm -f "$path/assignee"
    fi

    # Obtain milestone
    if [ "$(jq -r ".[$i].milestone" issue-body)" = null ] ; then
      if [ -r "$path/milestone" ] ; then
	git rm "$path/milestone" || trans_abort
      fi
    else
      jq -r ".[$i].milestone.title" issue-body >"$path/milestone" || trans_abort
      git add "$path/milestone" || trans_abort
    fi

    if [ "$provider" = gitlab ] ; then

      # Due Date
      duedate=$(jq -r ".[$i].due_date" issue-body)
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
      timespent=$(jq -r ".[$i].time_stats.total_time_spent" issue-body)
      if [ "$timespent" = '0' ] ; then
        if [ -r "$path/timespent" ] ; then
          git rm "$path/timespent" || trans_abort
        fi
      else
        echo "$timespent" >"$path/timespent" || trans_abort
        git add "$path/timespent" || trans_abort
      fi
      
      # Timeestimate
      timeestimate=$(jq -r ".[$i].time_stats.time_estimate" issue-body)
      if [ "$timeestimate" = '0' ] ; then
        if [ -r "$path/timeestimate" ] ; then
          git rm "$path/timeestimate" || trans_abort
        fi
      else
        echo "$timeestimate" >"$path/timeestimate" || trans_abort
        git add "$path/timeestimate" || trans_abort
      fi

      # Weight
      weight=$(jq -r ".[$i].weight" issue-body)
      if [ "$weight" = 'null' ] ; then
        if [ -r "$path/weight" ] ; then
          git rm "$path/weight" || trans_abort
        fi
      else
        echo "$weight" > "$path/weight" || trans_abort
        git add "$path/weight" || trans_abort
      fi
    fi

    # Create description
    jq -r ".[$i].title" issue-body >/dev/null || trans_abort
    jq -r ".[$i].$jdesc" issue-body >/dev/null || trans_abort
    {
      jq -r ".[$i].title" issue-body
      echo
      jq -r ".[$i].$jdesc" issue-body
    } |
    tr -d \\r >"$path/description"

    git add "$path/description" "$path/tags" imports || trans_abort
    if ! git diff --quiet HEAD ; then
      name=${name:-$(jq -r ".[$i].$juser" issue-body)}
      GIT_AUTHOR_DATE=$(jq -r ".[$i].updated_at" issue-body) \
	commit "gi: Import issue #$issue_number from $provider" \
	"Issue URL: https://$provider.com/$user/$repo/issues/$issue_number" \
	--author="$name <$name@users.noreply.$provider.com>"
      echo "Imported/updated issue #$issue_number as $(short_sha "$sha")"
    fi

    # Import issue comments
    import_comments "$user" "$repo" "$issue_number" "$sha" "$provider"
  done
}

export_issues()
{
  local i import_dir sha url provider user repo flag attr_expand OPTIND sha num

  while getopts e flag ; do    
    case $flag in    
    e)    
      # global flag to enable escape sequence 
      attr_expand=1    
      ;;    
    ?)    
      usage_export
      ;;    
    esac    
  done    
  shift $((OPTIND - 1));    
 
  test -n "$2" -a -n "$3" || usage_export
  test "$1" = github -o "$1" = gitlab || usage_export
  provider=$1
  user="$2"
  repo="$3"

  cdissues
  test -d "imports/$provider/$user/$repo" || error "No local issues found for this repository."

  # For each issue in the respective import dir
  for i in "imports/$provider/$user/$repo"/[1-9]* ; do
    sha=$(cat "$i/sha")
    # extract number
    num=$(echo "$i" | grep -o '/[1-9].*$' | tr -d '/')
    echo "Exporting issue $sha as #$num"
    create_issue -u "$num" "$sha" "$provider" "$user" "$repo"
    rm -f create-body create-header

  done
}
# Return the next page API URL specified in the header with the specified prefix
# Header examples (easy and tricky)
# Link: <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="next", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="last", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="first"
# Link: <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="prev", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="next", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=3>; rel="last", <https://api.github.com/repositories/146456308/issues?state=all&per_page=1&page=1>; rel="first"
rest_next_page_url()
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
' "$1"-header
}

# Import issues from specified source (currently github and gitlab)
sub_import()
{
  local endpoint user repo begin_sha provider

  test "$1" = github -o "$1" = gitlab -a -n "$2" -a -n "$3" || usage_import
  provider="$1"
  # convert to lowercase to avoid duplicates
  user="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
  repo="$(echo "$3" | tr '[:upper:]' '[:lower:]')"

  cdissues

  prerequisite_command jq
  prerequisite_command curl

  begin_sha=$(git rev-parse HEAD)

  mkdir -p "imports/$provider/$user/$repo"
  # Process issues page by page
  trans_start
    if [ "$provider" = github ] ; then
      endpoint="https://api.github.com/repos/$user/$repo/issues?state=all"
    else
      # if $repo contains '/' then it's part of a group and needs to be escaped
      local escrepo
      escrepo=$(urlescape "$repo")
      endpoint="https://gitlab.com/api/v4/projects/$user%2F$escrepo/issues"
    fi
  while true ; do
    rest_api_get "$endpoint" issue "$provider"
    import_issues "$user" "$repo" "$provider"

    # Return if no more pages
    if ! grep -q '^Link:.*rel="next"' issue-header ; then
      break
    fi

    # Move to next point
    endpoint=$(rest_next_page_url issue)
  done

  rm -f issue-header issue-body comments-header comments-body

  # Mark last import SHA, so we can use this for merging 
  if [ "$begin_sha" != "$(git rev-parse HEAD)" ] ; then
    local checkpoint="imports/$provider/$user/$repo/checkpoint"
    git rev-parse HEAD >"$checkpoint"
    git add "$checkpoint"
    commit "gi: Import issues from $provider checkpoint" \
    "Issues URL: https://$provider.com/$user/$repo/issues"
  fi
}

usage_exportall()
{
  cat <<\USAGE_exportall_EOF
gi new usage: git issue list [-a] provider user repo
USAGE_exportall_EOF
  exit 2
}

# Export all not already present issues to GitHub/GitLab repo
sub_exportall()
{
  local all provider user repo flag OPTIND shas
  while getopts a flag ; do
    case "$flag" in
    a)
      all='-a'
      ;;
    ?)
      usage_exportall
      ;;
  esac
done
shift $((OPTIND - 1));

test "$1" = github -o "$1" = gitlab || usage_exportall
test -n "$2" -a -n "$3" || usage_exportall
provider="$1"
user="$2"
repo="$3"

# Create list of relevant shas sorted by date
shas=$(sub_list -l %i -o %c "$all"| sed '/^$/d' | tr '\n' ' ')

# Remove already exported issues
#TODO
if [ -d ".issues/imports/$provider/$user/$repo" ] ; then
  for i in ".issues/imports/$provider/$user/$repo/"[1-9]* ; do
    shas=$(echo "$shas" | sed "s/$(head -c 7 "$i/sha")//")
  done
fi

for i in $shas ; do
  echo "Creating issue $i..."
  create_issue "$i" "$provider" "$user" "$repo"
done
}
