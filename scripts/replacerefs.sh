#!/bin/sh
# Filter an issue by replacing all references to issues in repo source to references in repo target
# replacerefs sourcerepo targetrepo

test -n "$2" || exit 2
expr "$1" : '.*/.*' > /dev/null || exit 2
expr "$2" : '.*/.*' > /dev/null || exit 2
sourcerepo=$1
targetrepo=$2
string=$(cat description)
refs=$(echo "$string" | grep -o '\([^[[:alnum:]_]\|^\)#[0-9]\+\([^][:alnum:]_]\|$\)' | grep -o '[0-9]\+' | sort | uniq)
for ref in $refs ; do
  test -d "../../../imports/$sourcerepo/$ref" || echo "Warning: Couldn't find $sourcerepo/$ref" 1>&2
  newref=$(git issue show "$(cat "../../../imports/$sourcerepo/$ref/sha")" |
  grep -i "${targetrepo%%/*} issue: #[0-9]\+ at ${targetrepo#*/}" | grep -o '#[0-9]\+')
  # if not found, replace the ref with a link to the original issue
  if [ -z "$newref" ] ; then
    echo "Warning: Couldn't find $sourcerepo/$ref issue in $targetrepo" 1>&2
    newref="[#$ref](https://${sourcerepo%%/*}\.com/${sourcerepo#*/}/issues/$ref)"
  fi

  string=$(echo "$string" | sed "s?\([^[[:alnum:]_]\|^\)#$ref\([^][:alnum:]_]\|$\)?\1$newref\2?g")
done
echo "$string" > description
