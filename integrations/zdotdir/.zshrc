# Shade zsh shell integration — ZDOTDIR shim (.zshrc stage, interactive shells).
#
# Loads the user's real ~/.zshrc untouched, then layers Shade's additions ONLY
# where the user hasn't set them up (augment, never override). See .zshenv in
# this directory for the mechanism.

# Recursion guard — restore the user's dir and bail if we re-enter.
if [[ -n $SHADE_SHELL_INTEGRATION ]]; then
	if [[ $SHADE_USER_ZDOTDIR_SET == 1 ]]; then
		ZDOTDIR=$SHADE_USER_ZDOTDIR
	else
		unset ZDOTDIR
	fi
	return
fi
SHADE_SHELL_INTEGRATION=1

# Point HISTFILE back at the user's home before their .zshrc runs, so history
# isn't written into Shade's (read-only) shim dir.
if [[ $SHADE_INJECTION == 1 ]]; then
	HISTFILE=$SHADE_USER_ZDOTDIR/.zsh_history
fi

# 1. Run the user's real .zshrc first — their PATH/aliases/prompt/keybindings win.
if [[ $SHADE_INJECTION == 1 && $options[norcs] == off && -f $SHADE_USER_ZDOTDIR/.zshrc ]]; then
	SHADE_USER_ZDOTFILE=$SHADE_USER_ZDOTDIR/.zshrc
	if [[ $SHADE_USER_ZDOTDIR_SET == 1 ]]; then
		ZDOTDIR=$SHADE_USER_ZDOTDIR
	else
		unset ZDOTDIR
	fi
	. "$SHADE_USER_ZDOTFILE"
	if (( ${+ZDOTDIR} )); then
		SHADE_USER_ZDOTDIR=$ZDOTDIR
		SHADE_USER_ZDOTDIR_SET=1
	else
		SHADE_USER_ZDOTDIR=$HOME
		SHADE_USER_ZDOTDIR_SET=0
	fi
	ZDOTDIR=$SHADE_SHIM_ZDOTDIR
	unset SHADE_USER_ZDOTFILE
fi

# 2. Completion — only if the user hasn't already initialised it (no oh-my-zsh,
#    bare ~/.zshrc, …). `compdef` exists exactly when compinit has run; -i skips
#    the insecure-directory prompt so startup never blocks for input.
if ! whence compdef >/dev/null 2>&1; then
	autoload -Uz compinit
	() {
		local dump=${XDG_CACHE_HOME:-$HOME/.cache}/shade
		[[ -d $dump ]] || command mkdir -p $dump 2>/dev/null
		compinit -i -d $dump/zcompdump
	}
	zstyle ':completion:*' menu select
	zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
fi

# 3. Shade's OSC 133 prompt marks (⌘⇧↑ / ⌘⇧↓ / ⌘⇧O). Additive and idempotent.
if [[ -r $SHADE_INTEGRATION_DIR/shade.zsh ]]; then
	. $SHADE_INTEGRATION_DIR/shade.zsh
fi

# Non-login shells and shells that disabled RCS never reach our .zlogin;
# restore ZDOTDIR for them here. Shade normally uses the .zlogin path.
if [[ $options[login] == off || $options[norcs] == on ]]; then
	if [[ $SHADE_USER_ZDOTDIR_SET == 1 ]]; then
		ZDOTDIR=$SHADE_USER_ZDOTDIR
	else
		unset ZDOTDIR
	fi
fi
