# .bashrc - User bash configuration
# This file is copied to each new user's home directory

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Custom aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'

# Custom prompt
PS1='[\u@\h \W]\$ '

# Custom environment variables
export EDITOR=vim
