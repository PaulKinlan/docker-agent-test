# .bashrc — Agent user shell configuration
# Populated from /etc/skel when the user is created via create-agent.sh

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'

# Prompt — shows username so you know which agent you're in
PS1='[\u@\h \W]\$ '

# Editor
export EDITOR=vim

# Agent environment
export AGENT_USER="$(whoami)"
export AGENT_HOME="$HOME"
