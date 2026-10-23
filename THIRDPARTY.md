# Third-party software

Shade redistributes the following open-source libraries via Swift Package
Manager. Their license terms are reproduced below as required by the MIT
permission notice.

---

## SwiftTerm

- **Repository:** https://github.com/migueldeicaza/SwiftTerm
- **Distribution:** Swift Package Manager dependency on a
  [rebase-tracked fork](https://github.com/tavvet/SwiftTerm), based on upstream
  `v1.99.1` and published on branch `shade/update-1.99.1`. Shade pins revision
  `850f6469329bada193981efa8a7e6ccd3920792e`, preserved by tag
  `shade-pin-2026-10-23-r2`. The fork carries four approved feature patches
  and a follow-up link-background rendering fix.
- **Modifications:**
  - Preserved configurable link underline color and a 35% cell-background tint
    through `linkHighlightColor`, without replacing the cell's foreground color.
    `nil` preserves upstream rendering.
  - Added atomic keyboard-selection commands that anchor at the live cursor
    and return copied selection coordinates.
  - Added a local clear-previous-output command that preserves pending input,
    cursor position and parser state without sending bytes to the PTY.
  - Extended copied OSC events with parser-time geometry, buffer identity,
    geometry generation and timestamps.

  Shell integration, shortcut routing, cut, prompt history and command timing
  remain in Shade, using SwiftTerm's public copied-state APIs and the narrow
  fork commands above. The complete current and historical patch inventory is
  documented in
  [the fork-maintenance guide](https://github.com/tavvet/shade/blob/main/docs/swiftterm-fork-migration.md).
- **License:** MIT
- **Used for:** VT100 / xterm terminal emulation and local PTY shell hosting.

```
Copyright (c) 2019-2026 Miguel de Icaza (https://github.com/migueldeicaza)
Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## KeyboardShortcuts

- **Repository:** https://github.com/sindresorhus/KeyboardShortcuts
- **License:** MIT
- **Used for:** Global hotkey registration and the SwiftUI shortcut recorder.

```
MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
