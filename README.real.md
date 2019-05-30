
# git-issue

This is a minimalist decentralized issue management system based on Git.
It has the following advantages over other systems.

* **No backend, no dependencies:**
  You can install and use _git issue_ with a single shell script.
  There's no need for a server or a database back-end, and the corresponding
  problems and requirements for their administration.
* **Decentralized asynchronous management:**
  Anyone can add, comment, and edit issues without requiring online access
  to a centralized server.
  There's no need for online connectivity; you can pull and push issues
  when you're online.
* **Transparent text file format:**
  Issues are stored as simple text files, which you can view, edit, share, and
  backup with any tool you like.
  There's no risk of loosing access to your issues because a server has
  failed.
* **Git-based:**
  Issues are changed and shared through Git.
  This provides _git issue_ with a robust, efficient, portable,
  and widely available infrastructure.
  It allows you to reuse your Git credentials and infrastructure, allows
  the efficient merging of work, and also provides a solid audit trail
  regarding any changes.
  You can even use Git and command-line tools directly to make sophisticated
  changes to your issue database.

## Installation

### Administrator installation
Clone the repo and run `make install` with appropriate privileges.

### Personal installation
Clone the repo and register a git alias to the `git-issue.sh` script:

```
git config --global alias.issue '!'"${REPO_PATH}/git-issue.sh"
```

If you are using a bash shell, you can also register the autocompletion
by adding the following to your .bashrc.

```
source ${REPO_PATH}/gi-completion.sh
```

### Backward compatibility with the gi command
For backward compatibility you can also use the original _gi_ command,
by copying `gi.sh` to someplace in your path.
In this case you must register the git alias to use the auto completion feature.
If you have administrative access you can install it with
`sudo install gi.sh /usr/local/bin/gi`.
For your personal use,
assuming that the directory `~/bin` exists and is in your path,
you can install it with `install gi.sh ~/bin/gi`.
You can even put `gi` in your project's current directory and run it from there.

### Portability and testing
The `git-issue.sh` script has been tested on:
Debian GNU/Linux, FreeBSD, macOS, and Cygwin.
If you're running _git issue* on another system,
run the `test.sh` script to verify
its operation, and (please) update this file.

### Requirements
`git-issue` requires the *jq* and *curl* utilities.
For running the tests *shellcheck* is also required.

## Use
You use _git issue_ with the following sub-commands.

### Start an issue repository
* `git issue clone`: Clone the specified remote repository.
* `git issue init`: Create a new issues repository in the current directory.
  The `-e` option uses an existing Git project repository.
### Work with an issue
* `git issue new`: Create a new open issue (with optional `-s` summary).
* `git issue show`: Show specified issue (and its comments with `-c`).
* `git issue comment`: Add an issue comment.
* `git issue edit`: Edit the specified issue's description
* `git issue tag`: Add (or remove with `-r`) a tag.
* `git issue milestone`: Specify (or remove with `-r`) the issue's milestone.
* `git issue weight`: Specify (or remove with `-r`) the issue's weight.
  The weight is a positive integer that serves as a measure of importance.
* `git issue duedate`: Specify (or remove with `-r`) the issue's due date.
  The command accepts all formats supported by the `date` utility.
* `git issue timeestimate`: Specify (or remove with `-r`) a time estimate for this issue.
  Time estimates can be given in a format accepted by `date`,
  however bear in mind that it represents a time interval, not a date.
* `git issue timespent` Specify (or remove with `-r`) the time spent working on an issue so far.
  Follows the same format outlined above.
  If the `-a` option is given, the time interval will be added together with the existing one.
* `git issue assign`: Assign (or remove `-r`) an issue to a person.
  The person is specified with his/her email address.
  The form `@name` or `name@` can be used as a shortcut, provided it
  uniquely identifies an existing assignee or committer.
* `git issue attach`: Attach (or remove with `-r`) a file to an issue.
* `git issue watcher`: Add (or remove with `-r`) an issue watcher.
* `git issue close`: Remove the `open` tag, add the closed tag
### Show multiple issues
* `git issue list`: List open issues (or all with `-a`).
   An optional argument can show issues matching a tags or milestone.
* `git issue list -l formatstring`: This will list issues in the specified format, given as an argument to `-l`.
   The following escape sequences can be used:
   
   - `%n` : newline
   - `%i` : issue ID
   - `%c` : creation date
   - `%d` : due date
   - `%e` : time estimate
   - `%s` : time spent
   - `%w` : weight
   - `%M` : Milestone
   - `%A` : Assignee(s)
   - `%T` : Tags
   - `%D` : Description(first line)

   If the format string is one of: (`oneline`, `short` or `full`) it will interpreted as the corresponding preset.
   
   Optionally, one of the above given with `-o` will order based on this field(reverse order with `-r`).
   
### Synchronize with remote repositories
* `git issue push`: Update remote Git repository with local changes.
* `git issue pull`: Update local Git repository with remote changes.
* `git issue import`: Import/update GitHub issues from the specified project.
  If the import involves more than a dozen of issues or if the repository
  is private, set the environment variable `GI_CURL_ARGS` to an argument
  that when passed to the _curl_ program will supply GitHub the appropriate
  API authentication.
  For example, run the following command: `echo "Authorization: token  badf00ddead9bfee8f3c19afc3c97c6db55fcfde" >$HOME/.token; export GI_CURL_ARGS='-H @$HOME/.token'`
  You can create the authorization token through
  [GitHub settings](https://github.com/settings/tokens/new).
### Help and debug
* `git issue help`: Display help information about git issue.
* `git issue log`: Output a log of changes made
* `git issue git`: Run the specified Git command on the issues repository.

Issues and comments are specified through the SHA hash associated with the
parent of the commit that opened them, which is specifically crafted for
that element and can be used to derive its date and author.

## Internals
All data are stored under `.issues`, which should be placed under `.gitignore`,
if it will coexist with another Git-based project.
The directory contains the following elements.
* A `.git` directory contains the Git data associated with the issues.
* A `config` file with configuration data.
* An `imports` directory contains details about imported issues.
  * The `sha` file under `import/github/<user>/<repo>/<number>` contains the
    _git-issue_ SHA corresponding to an imported GitHub _number_ issue.
  * The `sha` file under `import/github/<user>/<repo>/<number>/comments/<number>`
    contains the _git-issue_ comment SHA corresponding to an imported GitHub
    _number_ comment.
  * The file `import/github/<user>/<repo>/checkpoint` contains the SHA
    of the last imported or updated issue.  This can be used for merging
    future updates.
* An `issues` directory contains the individual issues.
* Each issue is stored in a directory named `issues/xx/xxxxxxx...`,
    where the x's are the SHA of the issue's initial commit.
* Each issue can have the following elements in its directory.
  * A `description` file with a one-line summary and a description of the issue.
  * A `duedate` file with the due date stored in ISO-8601 format.
  * A `weight` file with the weight stored as a positive integer.
  * A `timespent` and `timeestimate` file with the time estimate and time spent respectively, stored in seconds.
  * A `comments` directory where comments are stored, each with the SHA of
    a commit containing the text `gi comment mark`
    _issue SHA_.
  * An `attachments` directory where the issue's attachments are stored.
  * A `tags` file containing the issue's tags, one in each line.
  * A `watchers` file containing the emails of persons to be notified when the issue changes (one per line).
  * An `assignee` file containing the email for the person assigned to the issue.
* A `templates` directory with message templates.

## Contributing
Contributions are welcomed through pull requests.
Before working on a new feature please look at open issues, and if no
corresponding issue is open, create one to claim priority over the task.
Contributions should pass tests and should be accompanied with a
corresponding test case and documentation update.
Note that to avoid duplicating information, the subcommands, the used files,
and usage examples, are automatically inserted into the script and its
documentation from the `README.md` file using the `sync-docs.sh` command.

## Example session
You can also view a video of the following session on [YouTube](https://youtu.be/9aKHTjtTbFs).

### Initialize issue repository

```
$ git issue init
Initialized empty Issues repository in /home/dds/src/gi/.issues
$ git issue new -s 'New issue entered from the command line'
Added issue e6a95c9
```

### Create a new issue (opens editor window)

```
$ git issue new
Added issue 7dfa5b7
```

### List open issues

```
$ git issue list
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line
```

### Add an issue comment (opens editor window)

```
$ git issue comment e6a95c9
Added comment 8c0d5b3
```

### Add a due date for the issue
```
$ git issue duedate "next Tuesday"
```

### Keep track of time spent on the issue
```
$ git issue timespent "2hours"
```

### Log additional time spent working on it
```
$ git issue timespent -a "4 hours"
```

### Add tag to an issue

```
$ git issue tag e6a9 urgent
Added tag urgent
```

### Add two more tags

```
$ git issue tag e6a9 gui crash
Added tag gui
Added tag crash
```

### Remove a tag

```
$ git issue tag -r e6a9 urgent
Removed tag urgent
```

### Assign issue

```
$ git issue assign e6a9 joe@example.com
Assigned to joe@example.com
```

### Add issue watcher

```
$ git issue watcher e6a9 jane@example.com
Added watcher jane@example.com
```

### List issues tagged as gui

```
$ git issue list gui
e6a95c9 New issue entered from the command line
```

### Push issues repository to a server

```
$ git issue git remote add origin git@github.com:dspinellis/gi-example.git
$ git issue git push -u origin master
Counting objects: 60, done.
Compressing objects: 100% (50/50), done.
Writing objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Total 60 (delta 8), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
 * [new branch]      master -> master
Branch master set up to track remote branch master from origin.
```

### Clone issues repository from server

```
$ git issue clone git@github.com:dspinellis/gi-example.git my-issues
Cloning into '.issues'...
remote: Counting objects: 60, done.
remote: Compressing objects: 100% (42/42), done.
remote: Total 60 (delta 8), reused 60 (delta 8), pack-reused 0
Receiving objects: 100% (60/60), 5.35 KiB | 0 bytes/s, done.
Resolving deltas: 100% (8/8), done.
Checking connectivity... done.
Cloned git@github.com:dspinellis/gi-example.git into my-issues
```

### List open issues

```
$ git issue list
7dfa5b7 An issue entered from the editor
e6a95c9 New issue entered from the command line
```

### Create new issue

```
$ git issue new -s 'Issue added on another host'
Added issue abc9adc
```

### Push changes to server

```
$ git issue push
Counting objects: 7, done.
Compressing objects: 100% (6/6), done.
Writing objects: 100% (7/7), 767 bytes | 0 bytes/s, done.
Total 7 (delta 0), reused 0 (delta 0)
To git@github.com:dspinellis/gi-example.git
   d6be890..740f9a0  master -> master
```

### Show issue added on the other host

```
$ git issue show 7dfa5b7
issue 7dfa5b7f4591ecaa8323716f229b84ad40f5275b
Author: Diomidis Spinellis <dds@aueb.gr>
Date:   Fri, 29 Jan 2016 01:03:24 +0200
Tags:   open

    An issue entered from the editor

    Here is a longer description.
```

### Show issue and comments

```
$ git issue show -c e6a95c9
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
```

### Pull in remote changes (on the original host)

```
$ git issue pull
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
```

### List open issues

```
$ git issue list
7dfa5b7 An issue entered from the editor
abc9adc Issue added on another host
e6a95c9 New issue entered from the command line
```

### Import issues from GitHub

```
$ git issue import github dspinellis git-issue-test-issues # Import GitHub issues
Imported/updated issue #3 as 0a27c66
Imported/updated issue #2 as feb2a2c
Imported/updated issue #2 comment 416631296 as f7de92c
Imported/updated issue #2 comment 416631349 as 03acf84
Imported/updated issue #2 comment 417048301 as 0cd48ed
Imported/updated issue #2 comment 417049466 as 325a581
Imported/updated issue #1 as bbe144d
$ git issue list
feb2a2c An open issue on GitHub with a description and comments
0a27c66 An open issue on GitHub with assignees and tags
$ git issue show 0a27c66
issue 0a27c6633f492e42bb2a24e6ae458482a4690a55
Author: dspinellis <dspinellis@users.noreply.github.com>
Date:   Thu, 30 Aug 2018 20:59:59 +0000
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
```

### Sub-command auto-completion

```
$ git issue [Tab]
assign   clone    comment  git      init     log      pull     show     watcher
attach   close    edit     help     list     new      push     tag
```

### Issue SHA auto-completion

```
$ git issue show [Tab]
7dfa5b7 - An issue entered from the editor
e6a95c9 - New issue entered from the command line
```


## Related work
* [deft](https://github.com/npryce/deft) developed in 2011 is based on
  the same idea.
  It requires Python and offers a GUI.
* [Bugs Everywhere](http://www.bugseverywhere.org/), also written in Python, supports many version control backends and offers a web interface.
* [bug](https://github.com/driusan/bug), inspired by Bugs Everywhere, written in Go, supports git and hg
* [git-bug](https://github.com/MichaelMure/git-bug), again written in Go, is a distributed bug tracker embedded in git.
* [git-appraise](https://github.com/google/git-appraise) is a distributed
  code review system for Git repos based again on Git.
* [Fossil](http://fossil-scm.org/) is a distributed version control software that also supports issue tracking and a wiki. It runs as a single executable.
* [SD (Simple Defects)], a (now defunct?) distributed bug tracking system based on a distributed database. It can import/export from/to foreign ticketing systems.

More historical references can be found in [this old LWN article on distributed bug tracking](https://lwn.net/Articles/281849/).
