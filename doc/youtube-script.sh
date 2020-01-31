$ git clone git@github.com:dspinellis/git-issue.git
Cloning into 'git-issue'...
remote: Enumerating objects: 1057, done.
remote: Counting objects: 100% (1057/1057), done.
remote: Compressing objects: 100% (260/260), done.
remote: Total 1683 (delta 559), reused 1029 (delta 538), pack-reused 626
Receiving objects: 100% (1683/1683), 494.52 KiB | 1.74 MiB/s, done.
Resolving deltas: 100% (947/947), done.
$ cd git-issue

$ sudo make install # Install
mkdir -p "/usr/local/share/man/man1"
mkdir -p "/usr/local/bin"
mkdir -p "/usr/local/lib"/git-issue
install git-issue.sh "/usr/local/bin"/git-issue
install lib/git-issue/import-export.sh "/usr/local/lib"/git-issue/import-export.sh
install -m 644 git-issue.1 "/usr/local/share/man/man1"/
mkdir -p /usr/local/etc/bash_completion.d
install -m 644 gi-completion.sh /usr/local/etc/bash_completion.d/git-issue

$ make install PREFIX=$HOME # Install for current user
install git-issue.sh "/home/dds/bin"/git-issue
install lib/git-issue/import-export.sh "/home/dds/lib"/git-issue/import-export.sh
install -m 644 git-issue.1 "/home/dds/share/man/man1"/
install -m 644 gi-completion.sh /home/dds/etc/bash_completion.d/git-issue

$ git issue init # Initialize issue repository
Initialized empty Issues repository in /home/dds/src/git-issue/.issues

$ git issue new -s 'New issue entered from the command line'
Added issue e6a95c9

$ git issue new # Create a new issue (opens editor window)
Added issue 7dfa5b7

$ git issue list # List open issues
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line

$ git issue comment e6a95c9 # Add an issue comment (opens editor window)
Added comment 8c0d5b3

$ git issue tag e6a9 urgent # Add tag to an issue
Added tag urgent

$ git issue tag e6a9 gui crash # Add two more tags
Added tag gui
Added tag crash

$ git issue tag -r e6a9 urgent # Remove a tag
Removed tag urgent

$ git issue assign e6a9 joe@example.com # Assign issue
Assigned to joe@example.com

$ git issue watcher e6a9 jane@example.com # Add issue watcher
Added watcher jane@example.com

$ git issue list gui # List issues tagged as gui
e6a95c9 New issue entered from the command line

$ # Push issues repository to a server
$ git issue git remote add origin git@github.com:dspinellis/gi-example.git

$ git issue git push -u origin master
Counting objects: 60, done.
Compressing objects: 100% (50/50), done.
Writing objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Total 60 (delta 8), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
 * [new branch]      master -> master
Branch master set up to track remote branch master from origin.

$ # Clone issues repository from server
$ git issue clone git@github.com:dspinellis/gi-example.git my-issues
Cloning into '.issues'...
remote: Counting objects: 60, done.
remote: Compressing objects: 100% (42/42), done.
remote: Total 60 (delta 8), reused 60 (delta 8), pack-reused 0
Receiving objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Resolving deltas: 100% (8/8), done.
Checking connectivity... done.
Cloned git@github.com:dspinellis/gi-example.git into my-issues

$ git issue list # List open issues
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line

$ git issue new -s 'Issue added on another host' # Create new issue
Added issue abc9adc

$ git issue push # Push changes to server
Counting objects: 7, done.
Compressing objects: 100% (6/6), done.
Writing objects: 100% (7/7), 767 bytes | 0 bytes/s, done.
Total 7 (delta 0), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
   d6be890..740f9a0  master -> master

$ git issue show 7dfa5b7 # Show issue added on the other host
issue 7dfa5b7f4591ecaa8323716f229b84ad40f5275b
Author: Diomidis Spinellis <dds@aueb.gr>
Date:   Fri, 29 Jan 2016 01:03:24 +0200
Tags:   open

    An issue entered from the editor

    Here is a longer description.

$ git issue show -c e6a95c9 # Show issue and coments
issue e6a95c91b31ded8fc229a41cc4bd7d281ce6e0f1
Author: Diomidis Spinellis <dds@aueb.gr>
Date:   Fri, 29 Jan 2016 01:03:20 +0200
Tags:   open urgent gui crash
Watchers:       jane@example.com
Assigned-to: joe@example.com

    New issue entered from the command line

comment 8c0d5b3d77bf93b937cb11038b129f927d49e34a
Author: Diomidis Spinellis <dds@aueb.gr>
Date:   Fri, 29 Jan 2016 01:03:57 +0200

    First comment regarding the issue.


$ # On the original host
$ git issue pull # Pull in remote changes
remote: Counting objects: 7, done.
remote: Compressing objects: 100% (6/6), done.
remote: Total 7 (delta 0), reused 7 (delta 0), pack-reused 0
Unpacking objects: 100% (7/7), done.
From github.com:dspinellis/gi-example
   d6be890..740f9a0  master     -> origin/master
Updating d6be890..740f9a0
Fast-forward
 issues/ab/c9adc61025a3cb73b0c67470b65cefc133a8d0/description | 1 +
 issues/ab/c9adc61025a3cb73b0c67470b65cefc133a8d0/tags        | 1 +
 2 files changed, 2 insertions(+)
 create mode 100644 issues/ab/c9adc61025a3cb73b0c67470b65cefc133a8d0/description
 create mode 100644 issues/ab/c9adc61025a3cb73b0c67470b65cefc133a8d0/tags

$ git issue list # List open issues
7dfa5b7 An issue entered from the editor
abc9adc Issue added on another host
e6a95c9 New issue entered from the command line


$ # GitHub import functionality
$ mkdir github-project
$ cd github-project/
$ git issue init
Initialized empty issues repository in /home/dds/github-project/.issues

$ git issue import github dspinellis git-issue-test-issues # Import GitHub issues
Imported/updated issue #3 as 4a0b58a
Imported/updated issue #2 as 1e87224
Imported/updated issue #2 comment 416631296 as 11bf4e3
Imported/updated issue #2 comment 416631349 as 002e327
Imported/updated issue #2 comment 417048301 as 20aeee8
Imported/updated issue #2 comment 417049466 as a8a12ac
Imported/updated issue #1 as 3ea0e3e

$ git issue list
1e87224 An open issue on GitHub with a description and comments
4a0b58a An open issue on GitHub with assignees and tags

$ git issue show 4a0b58a
issue 4a0b58a4b7eb7e4e0a3e451746ccd687d9f45048
Author: dspinellis <dspinellis@users.noreply.github.com>
Date:   Thu, 30 Aug 2018 20:59:59 +0000
GitHub issue: #3 at dspinellis/git-issue-test-issues
Tags:   bug
        duplicate
        enhancement
        good first issue
        open
Assigned-to:    dspinellis
        louridas

    An open issue on GitHub with assignees and tags

    Description

Edit History:
* Thu, 30 Aug 2018 20:59:59 +0000 by dspinellis
* <dspinellis@users.noreply.github.com>

$ git issue milestone 4a0b58a R-3.5 # Add milestone
Added milestone R-3.5

$ git issue duedate 4a0b58a 2038-01-18 # Set a nice due date
Added duedate 2038-01-18T00:00:00+02:00

$ git issue close 1e87224 # Close another issue
Added tag closed
Removed tag open

$ git issue export github dspinellis git-issue-test-issues # Export modified issues
Issue 3ea0e3ef91619eedfdfd25f93135a9dd99e3435b not modified, skipping...
Exporting issue 1e872249eebe4f984d188700115484d75ab28cd8 as #2
Comment 11bf4e3c5a950142eff5579c23f805ee67c19a93 not modified, skipping...
Comment 002e327f35f76111ce2693969de3cfff2f35d6c7 not modified, skipping...
Comment 20aeee8898c28bc6793fb6114baf2e41397c0d8e not modified, skipping...
Comment a8a12aca79e8a14c09f91e5faaa8ce79a1b9f180 not modified, skipping...
Exporting issue 4a0b58a4b7eb7e4e0a3e451746ccd687d9f45048 as #3
Creating new Milestone R-3.5...

$ 
