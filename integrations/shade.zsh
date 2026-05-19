# Shade prompt-mark integration (OSC 133) for zsh.
#
# Enables ⌘⇧↑ / ⌘⇧↓ to jump between shell prompts in the Shade terminal
# and ⌘⇧O to copy the previous command's output to the clipboard.
#
# Source this from your ~/.zshrc:
#   # Homebrew install:
#   source "$(brew --prefix)/share/shade/shade.zsh"
#   # From-source checkout:
#   source /path/to/shade/integrations/shade.zsh

_shade_osc133() { printf '\e]133;%s\a' "$1" }
_shade_precmd()  { _shade_osc133 "D;$?"; _shade_osc133 A }
_shade_preexec() { _shade_osc133 C }

precmd_functions+=(_shade_precmd)
preexec_functions+=(_shade_preexec)
