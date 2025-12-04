Here are the **most commonly used find parameters on macOS (and Unix in
general)** --- the ones you\'ll actually use day-to-day:

**🔍 Common find Search Filters**

**By Name**

find . -name \"\*.txt\"

Case-insensitive:

find . -iname \"\*.jpg\"

**By Type**

find . -type f \# files

find . -type d \# directories

find . -type l \# symlinks

**By Size**

find . -size +10M \# larger than 10 MB

find . -size -500k \# smaller than 500 KB

**By Time**

Modified:

find . -mtime -1 \# modified in last 24 hours

find . -mtime +7 \# modified more than 7 days ago

Accessed:

find . -atime -2

Changed (permissions/owner/etc.):

find . -ctime -1

**By Permissions**

find . -perm 644

find . -perm -u+x \# user executable

**By User / Group**

find /var/log -user root

find . -group staff

**⚙️ Common Actions**

**Print results (default, but useful in combos)**

find . -print

**Exec a command for each result**

find . -name \"\*.log\" -exec rm {} \\;

Use + for batching:

find . -name \"\*.log\" -exec rm {} +

**Delete matching files**

find . -name \"\*.tmp\" -delete

**Just list the filenames**

find . -type f -print0 \| xargs -0 ls -l

**🧠 Useful combos you'll actually use**

**1. Find big files**

find . -type f -size +100M

**2. Find recently changed files**

find . -type f -mtime -2

**3. Find file by name, ignore case**

find . -iname \"notes\*\"

**4. Find all directories named \"node_modules\"**

find . -type d -name node_modules

**5. Delete .DS_Store everywhere**

find . -name \".DS_Store\" -delete

**📌 Extra: GNU find vs macOS find**

macOS uses **BSD find**, which is missing some GNU features (e.g.
-printf).

You can get GNU find with:

brew install findutils

Then use:

gfind \...

If you want, I can also give:

- a cheat-sheet version

- most **dangerous** vs **safe** examples

- a "find + grep" combo guide

**You said:**

yes cheat sheet version

**ChatGPT said:**

Here's a **compact macOS find cheat sheet** --- minimal, practical, and
ready to paste into Notes or desktop:

**FIND -- ESSENTIAL CHEAT SHEET (macOS / BSD)**

**Basic structure:**

find \<path\> \<tests\> \<actions\>

**Common Tests**

**Name**

-name \"\*.txt\"

-iname \"\*.jpg\" \# ignore case

**Type**

-type f \# file

-type d \# directory

-type l \# symlink

**Size**

-size +10M \# \>10 MB

-size -500k \# \<500 KB

**Time**

-mtime -1 \# modified \<1 day ago

-mtime +7 \# modified \>7 days ago

-atime -2 \# accessed \<2 days ago

-ctime -1 \# metadata changed \<1 day ago

**Permissions / Ownership**

-perm 644

-perm -u+x \# user executable

-user root

-group staff

**Common Actions**

-print \# default

-delete

-exec CMD {} \\; \# per file

-exec CMD {} + \# batch

**Useful Real Examples**

find . -type f -size +100M

find . -iname \"notes\*\"

find /var/log -user root

find . -name \".DS_Store\" -delete

find . -type d -name node_modules

find . -mtime -1 -exec ls -l {} \\;
