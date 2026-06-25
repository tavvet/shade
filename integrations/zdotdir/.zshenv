# Shade zsh shell integration — ZDOTDIR shim (.zshenv stage, runs first/always).
#
# When "shell enrichment" is on, Shade launches zsh with ZDOTDIR pointed at this
# directory and SHADE_USER_ZDOTDIR holding the user's real one. Each shim here
# sources the user's matching startup file, then restores ZDOTDIR to this dir so
# the next file zsh reads (.zprofile/.zshrc/.zlogin) is still ours. We never edit
# the user's dotfiles. Mechanism mirrors VS Code's terminal ZDOTDIR injection.

if [[ -f $SHADE_USER_ZDOTDIR/.zshenv ]]; then
	SHADE_ZDOTDIR=$ZDOTDIR
	ZDOTDIR=$SHADE_USER_ZDOTDIR

	# Skip if the user's ZDOTDIR is this very dir (would recurse).
	if [[ $SHADE_USER_ZDOTDIR != $SHADE_ZDOTDIR ]]; then
		. $SHADE_USER_ZDOTDIR/.zshenv
	fi

	# The user's .zshenv may itself have moved ZDOTDIR — re-capture it so the
	# later stages follow the user's intent, then hand control back to our dir.
	SHADE_USER_ZDOTDIR=$ZDOTDIR
	ZDOTDIR=$SHADE_ZDOTDIR
fi
