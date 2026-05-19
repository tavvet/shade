# Shade prompt-mark integration (OSC 133) for bash.
#
# Enables ⌘⇧↑ / ⌘⇧↓ to jump between shell prompts in the Shade terminal
# and ⌘⇧O to copy the previous command's output to the clipboard.
#
# Requires bash-preexec — see https://github.com/rcaloras/bash-preexec.
# Source bash-preexec.sh in ~/.bashrc first, then source this:
#   # Homebrew install (Cask drops Shade.app in /Applications):
#   source "/Applications/Shade.app/Contents/Resources/integrations/shade.bash"
#   # From-source checkout:
#   source /path/to/shade/integrations/shade.bash

_shade_osc133()  { printf '\e]133;%s\a' "$1"; }
_shade_precmd()  { _shade_osc133 "D;$?"; _shade_osc133 A; }
_shade_preexec() { _shade_osc133 C; }

precmd_functions+=(_shade_precmd)
preexec_functions+=(_shade_preexec)
