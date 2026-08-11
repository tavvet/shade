# Shade zsh shell integration — ZDOTDIR shim (.zprofile stage, login shells).
# See .zshenv in this directory for the mechanism.

if [[ -n $SHADE_PROFILE_INITIALIZED ]]; then
	return
fi
SHADE_PROFILE_INITIALIZED=1

if [[ $options[norcs] == off && -o login && -f $SHADE_USER_ZDOTDIR/.zprofile ]]; then
	SHADE_USER_ZDOTFILE=$SHADE_USER_ZDOTDIR/.zprofile
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
	# No later shim runs after `unsetopt RCS`, so restore immediately.
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
fi
