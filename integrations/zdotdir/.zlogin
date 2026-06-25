# Shade zsh shell integration — ZDOTDIR shim (.zlogin stage, login shells, last).
# See .zshenv in this directory for the mechanism.
#
# Final stage: permanently restore the user's ZDOTDIR (so nested zsh and child
# processes see the real value, not Shade's shim), then run the user's .zlogin.

if [[ -n $SHADE_LOGIN_INITIALIZED ]]; then
	return
fi
SHADE_LOGIN_INITIALIZED=1

ZDOTDIR=$SHADE_USER_ZDOTDIR
if [[ $options[norcs] == off && -o login && -f $ZDOTDIR/.zlogin ]]; then
	. $ZDOTDIR/.zlogin
fi
