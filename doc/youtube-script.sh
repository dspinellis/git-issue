$ git clone git@github.com:dspinellis/gi.git
Cloning into 'gi'...
remote: Counting objects: 75, done.
remote: Compressing objects: 100% (39/39), done.
remote: Total 75 (delta 42), reused 69 (delta 36), pack-reused 0
Receiving objects: 100% (75/75), 29.52 KiB | 0 bytes/s, done.
Resolving deltas: 100% (42/42), done.
Checking connectivity... done.
$ sudo install gi/gi.sh /usr/local/bin # Install
$ gi init # Initialize issue repository
Initialized empty Issues repository in /home/dds/src/gi/.issues
$ gi new -s 'New issue entered from the command line'
Added issue e6a95c9
$ gi new # Create a new issue (opens editor window)
Added issue 7dfa5b7
$ gi list # List open issues
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line
$ gi comment e6a95c9 # Add an issue comment (opens editor window)
Added comment 8c0d5b3
$ gi tag e6a9 urgent # Add tag to an issue
Added tag urgent
$ gi tag e6a9 gui crash # Add two more tags
Added tag gui
Added tag crash
$ gi tag -r e6a9 urgent # Remove a tag
Removed tag urgent
$ gi assign e6a9 joe@example.com # Assign issue
Assigned to joe@example.com
$ gi watcher e6a9 jane@example.com # Add issue watcher
Added watcher jane@example.com
$ gi list gui # List issues tagged as gui
e6a95c9 New issue entered from the command line
$ # Push issues repository to a server
$ gi git remote add origin git@github.com:dspinellis/gi-example.git
$ gi git push -u origin master
Counting objects: 60, done.
Compressing objects: 100% (50/50), done.
Writing objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Total 60 (delta 8), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
 * [new branch]      master -> master
Branch master set up to track remote branch master from origin.


$ # Clone issues repository from server
$ gi clone git@github.com:dspinellis/gi-example.git my-issues
Cloning into '.issues'...
remote: Counting objects: 60, done.
remote: Compressing objects: 100% (42/42), done.
remote: Total 60 (delta 8), reused 60 (delta 8), pack-reused 0
Receiving objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Resolving deltas: 100% (8/8), done.
Checking connectivity... done.
Cloned git@github.com:dspinellis/gi-example.git into my-issues
$ gi list # List open issues
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line
$ gi new -s 'Issue added on another host' # Create new issue
Added issue abc9adc
$ gi push # Push changes to server
Counting objects: 7, done.
Compressing objects: 100% (6/6), done.
Writing objects: 100% (7/7), 767 bytes | 0 bytes/s, done.
Total 7 (delta 0), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
   d6be890..740f9a0  master -> master
$ gi show 7dfa5b7 # Show issue added on the other host
issue 7dfa5b7f4591ecaa8323716f229b84ad40f5275b
Author: Diomidis Spinellis <dds@aueb.gr>
Date:   Fri, 29 Jan 2016 01:03:24 +0200
Tags:   open

    An issue entered from the editor

    Here is a longer description.
$ gi show -c e6a95c9 # Show issue and coments
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
$ gi pull # Pull in remote changes
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
$ gi list # List open issues
7dfa5b7 An issue entered from the editor
abc9adc Issue added on another host
e6a95c9 New issue entered from the command line
$ 
