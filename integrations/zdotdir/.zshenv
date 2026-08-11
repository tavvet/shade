# Shade zsh shell integration — ZDOTDIR shim (.zshenv stage, runs first/always).
#
# When "shell enrichment" is on, Shade launches zsh with ZDOTDIR pointed at this
# directory and SHADE_USER_ZDOTDIR holding the user's real one. Each shim here
# sources the user's matching startup file, then restores ZDOTDIR to this dir so
# the next file zsh reads (.zprofile/.zshrc/.zlogin) is still ours. We never edit
# the user's dotfiles. Mechanism mirrors VS Code's terminal ZDOTDIR injection.

SHADE_USER_ZDOTFILE=$SHADE_USER_ZDOTDIR/.zshenv
if [[ -f $SHADE_USER_ZDOTFILE && $SHADE_USER_ZDOTDIR != $SHADE_SHIM_ZDOTDIR ]]; then
	if [[ $SHADE_USER_ZDOTDIR_SET == 1 ]]; then
		ZDOTDIR=$SHADE_USER_ZDOTDIR
	else
		unset ZDOTDIR
	fi
	. "$SHADE_USER_ZDOTFILE"

	# A startup file can move or unset ZDOTDIR. Capture both its path and its
	# set/unset state so the next stage behaves exactly like a normal zsh.
	if (( ${+ZDOTDIR} )); then
		SHADE_USER_ZDOTDIR=$ZDOTDIR
		SHADE_USER_ZDOTDIR_SET=1
	else
		SHADE_USER_ZDOTDIR=$HOME
		SHADE_USER_ZDOTDIR_SET=0
	fi
fi
# If the user disabled RCS, zsh will not invoke another shim stage. Restore
# their final state here instead of leaving our private directory installed.
if [[ $options[norcs] == on ]]; then
	if [[ $SHADE_USER_ZDOTDIR_SET == 1 ]]; then
		ZDOTDIR=$SHADE_USER_ZDOTDIR
	else
		unset ZDOTDIR
	fi
else
	ZDOTDIR=$SHADE_SHIM_ZDOTDIR
fi
unset SHADE_USER_ZDOTFILE
