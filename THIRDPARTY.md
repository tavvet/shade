# Third-party software

Shade redistributes the following open-source libraries via Swift Package
Manager. Their license terms are reproduced below as required by the MIT
permission notice.

---

## SwiftTerm

- **Repository:** https://github.com/migueldeicaza/SwiftTerm
- **Distribution:** Swift Package Manager dependency on a
  [rebase-tracked fork](https://github.com/tavvet/SwiftTerm) (`main`, pinned by
  revision) that carries one local patch relative to its audited upstream base.
  The exact base and pin are recorded in the fork-maintenance guide below;
  `upstream/main` may advance between explicit syncs.
- **Modifications:**
  - Added a public `linkHighlightColor: NSColor?` on the macOS
    `TerminalView`. When set, highlighted links use that color for their
    underline and a subtle cell-background tint; `nil` preserves upstream
    rendering.

  Keyboard selection, cut and OSC 133 tracking are implemented in Shade using
  SwiftTerm's public API or the open PTY view; they are not fork patches. The
  complete current and historical patch inventory is documented in
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
