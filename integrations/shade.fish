# Shade prompt-mark integration (OSC 133) for fish.
#
# Enables ⌘⇧↑ / ⌘⇧↓ to jump between shell prompts in the Shade terminal
# and ⌘⇧O to copy the previous command's output to the clipboard.
#
# Source this from your ~/.config/fish/config.fish:
#   # Homebrew install (Cask drops Shade.app in /Applications):
#   source /Applications/Shade.app/Contents/Resources/integrations/shade.fish
#   # From-source checkout:
#   source /path/to/shade/integrations/shade.fish

function _shade_osc133
    printf '\e]133;%s\a' $argv[1]
end

function _shade_precmd --on-event fish_prompt
    _shade_osc133 "D;$status"
    _shade_osc133 A
end

function _shade_preexec --on-event fish_preexec
    _shade_osc133 C
end
