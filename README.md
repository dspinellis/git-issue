[![Build Status](https://travis-ci.org/eellak/gsoc2019-git-issue.svg?branch=gsoc-2019)](https://travis-ci.org/eellak/gsoc2019-git-issue)
#  <img src="https://developers.google.com/open-source/gsoc/resources/downloads/GSoC-icon-192.png" width="40"> GSoC 2019 Project - Git Issue <img src="https://developers.google.com/open-source/gsoc/resources/downloads/GSoC-icon-192.png" width="40">
This is the home repository of the GSoC 2019 project, aiming to extend git-issue with full import and export capabilities towards GitHub and GitLab. The project is supervised by the Open Technologies Aliance - GFOSS, and the following mentors: Diomidis Spinellis, Kostas Papadimas, Alexios Zavras. For the actual README, see [README.real.md](https://github.com/eellak/gsoc2019-git-issue/blob/gsoc-2019/README.real.md).

# About the project
`Git-issue` is a minimalist issue management system based on `git`. It strives to be **simple to use**, **decentralized**, and in line with existing **Unix software philosophy and design**.
Currently, `git-issue` can import data from GitHub's issue management interface, but **not** export them. This is limiting in the following ways:
+  It can lead to out-of-sync issue databases between git-issue and *GitHub*, which means that users have to access both to get the whole picture
+ It prevents usage of git-issue as an **one-stop solution**, since GitHub's interface still needs to be used to process issues opened in GitHub
+ It limits potential use cases, since `git-issue` has to compete with ubiquitous issue management solutions such as *GitHub/Gitlab*, instead of synergizing with them

Thus, adding export capabilities would complete the round-trip integration between `git-issue` and *GitHub*, and pave the way to wider adoption. The same argument can be made with *GitLab*, for which neither export nor import capability is currently supported. This proposal aims to add import and import/export functionality for GitHub and GitLab respectively.

# Timeline
## ~~May 7-May 26 (before coding starts)~~ :heavy_check_mark:
- Familiarize with the existing codebase and in particular with the current GitHub import implementation. :heavy_check_mark:
- Familiarize with the GitHub/GitLab API, as well as the HTTP REST model, which both utilize. :heavy_check_mark:
- Engage with the project’s community, by participating in discussions about the proposed features and taking the feedback into consideration for the rest of the program. :heavy_check_mark:
## ~~May 27-June 5 (coding period begins)~~ :heavy_check_mark:
- Add time tracking and weight attributes to git-issue :heavy_check_mark: [new_attributes branch](https://github.com/eellak/gsoc2019-git-issue/tree/new_attributes) **[merged]**
- Write automated tests and documentation on the new attributes :heavy_check_mark:
## ~~June 6-June 17~~ :heavy_check_mark:
- Implement issue exporting to GitHub :heavy_check_mark:
- Test and debug(through both the existing automated testing system and manual tests) both import and export functionality :heavy_check_mark:
- This concludes the GitHub integration part :heavy_check_mark:
## ~~June 18-June 21~~ :heavy_check_mark:
- Test and debug both import and export functionality :heavy_check_mark:
- Write automated tests and documentation on the above :heavy_check_mark:
- [github_export branch](https://github.com/eellak/gsoc2019-git-issue/tree/github_export) **[merged]**
## ~~June 28-July 11~~ :heavy_check_mark:
- Work shifts towards GitLab integration.
- Implement GitLab import functionality. :heavy_check_mark:
## ~~July 12-July 19~~ :heavy_check_mark:
- Test and debug GitLab import :heavy_check_mark:
- Write documentation and automated tests on GitLab import :heavy_check_mark:
- [gitlab_import branch](https://github.com/eellak/gsoc2019-git-issue/tree/gitlab_import) **[merged]**
## July 26-August 10 :heavy_check_mark:
- Implement GitLab export functionality. :heavy_check_mark:
- Test and debug GitLab import/export functionality. :heavy_check_mark:
## August 11-August 19 :alarm_clock:
- Final integration testing, ensuring with the help of my mentor that the code quality is up to standard
- Ensure interface consistency between the GitLab and GitHub implementations
- Final Documentation writing

