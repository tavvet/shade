# Shade prompt-mark integration (OSC 133) for zsh.
#
# Enables ⌘⇧↑ / ⌘⇧↓ to jump between shell prompts in the Shade terminal
# and ⌘⇧O to copy the previous command's output to the clipboard.
#
# Source this from your ~/.zshrc:
#   # Installed application:
#   source "/Applications/Shade.app/Contents/Resources/integrations/shade.zsh"
#   # From-source checkout:
#   source /path/to/shade/integrations/shade.zsh

_shade_osc133() { printf '\e]133;%s\a' "$1" }
_shade_precmd()  { _shade_osc133 "D;$?"; _shade_osc133 A }
_shade_preexec() { _shade_osc133 C }

# Idempotent: avoid double-registration if sourced twice (e.g. a manual line in
# ~/.zshrc plus Shade's ZDOTDIR injection), which would emit each mark twice.
(( ${precmd_functions[(I)_shade_precmd]} ))   || precmd_functions+=(_shade_precmd)
(( ${preexec_functions[(I)_shade_preexec]} )) || preexec_functions+=(_shade_preexec)
