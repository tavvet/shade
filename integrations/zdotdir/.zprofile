# Shade zsh shell integration — ZDOTDIR shim (.zprofile stage, login shells).
# See .zshenv in this directory for the mechanism.

if [[ -n $SHADE_PROFILE_INITIALIZED ]]; then
	return
fi
SHADE_PROFILE_INITIALIZED=1

if [[ $options[norcs] == off && -o login && -f $SHADE_USER_ZDOTDIR/.zprofile ]]; then
	SHADE_ZDOTDIR=$ZDOTDIR
	ZDOTDIR=$SHADE_USER_ZDOTDIR
	. $SHADE_USER_ZDOTDIR/.zprofile
	ZDOTDIR=$SHADE_ZDOTDIR
fi
