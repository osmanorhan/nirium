# ~/.zshrc — nirium default shell config
# Installed by the nirium installer. Safe to customise — the installer
# will NOT overwrite this file on re-runs.

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS       # no duplicate consecutive entries
setopt HIST_IGNORE_ALL_DUPS   # remove older duplicates from history
setopt HIST_FIND_NO_DUPS      # don't show duplicates in search
setopt HIST_REDUCE_BLANKS     # strip extra whitespace
setopt INC_APPEND_HISTORY     # write immediately, not on shell exit
setopt SHARE_HISTORY          # share history across terminals

# ── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit
compinit

zstyle ':completion:*' menu select           # arrow-key menu
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
setopt COMPLETE_IN_WORD       # complete from anywhere in the word
setopt AUTO_MENU              # show menu on second tab
setopt LIST_PACKED            # compact completion lists

# ── Directory shortcuts ───────────────────────────────────────────────────────
setopt AUTO_CD                # type a dir name to cd into it
setopt AUTO_PUSHD             # push dirs onto the stack on cd
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
alias d='dirs -v'             # show dir stack
for i in {1..9}; do alias "$i"="cd +${i}"; done  # jump by stack index

# ── Plugins (installed by pacman) ─────────────────────────────────────────────
# Fish-like autosuggestions (grey ghost text as you type)
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# Syntax highlighting (must load last)
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Additional completions
[[ -d /usr/share/zsh/site-functions ]] && fpath+=(/usr/share/zsh/site-functions)

# ── Key bindings ──────────────────────────────────────────────────────────────
bindkey -e                            # emacs-style (Ctrl+A/E, etc.)
bindkey '^[[A' history-search-backward  # Up arrow → history search
bindkey '^[[B' history-search-forward   # Down arrow → history search
bindkey '^[[1;5C' forward-word           # Ctrl+Right → jump word
bindkey '^[[1;5D' backward-word          # Ctrl+Left → jump word
bindkey '^[[3~' delete-char              # Delete key
bindkey '^H' backward-delete-word        # Ctrl+Backspace → delete word

# ── Aliases ───────────────────────────────────────────────────────────────────
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -lh --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias v='nvim'
alias vi='nvim'
alias vim='nvim'

alias g='git'
alias ga='git add'
alias gc='git commit'
alias gco='git checkout'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'
alias gp='git push'
alias gs='git status'
alias gst='git stash'

alias p='sudo pacman'
alias y='yay'
alias pss='pacman -Ss'    # search
alias psi='pacman -Si'    # info
alias pqs='pacman -Qs'   # query installed

alias t='tmux'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'

# ── Starship prompt ───────────────────────────────────────────────────────────
if command -v starship > /dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
