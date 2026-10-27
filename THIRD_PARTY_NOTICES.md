# Third-party notices

DynamicNotch is licensed under GPL-3.0-or-later. It adapts code and techniques from the projects below. Each adapted file says so in a comment at its top.

## DynamicNotchKit

- Source: https://github.com/MrKai77/DynamicNotchKit
- Licence: MIT. Copyright (c) 2025 Kai Azim
- Used for: the notch-shape curve (concave top shoulders drawn with quadratic curves) and the NSScreen notch-size maths (`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`).

```
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

## boring.notch

- Source: https://github.com/TheBoredTeam/boring.notch
- Licence: GPL-3.0. Copyright (c) TheBoredTeam and contributors
- Used for: the island panel configuration (non-activating panel, `.mainMenu + 3` level, collection behaviour) and the notch width fudge factor.

## MacroVisionKit

- Source: https://github.com/TheBoredTeam/MacroVisionKit
- Licence: MIT. Copyright (c) 2024 github.com/theboringhumane
- Used for: the technique of detecting fullscreen spaces per display by reading `CGSCopyManagedDisplaySpaces` (a space with a `TileLayoutManager` is fullscreen). DynamicNotch reimplements it as a `dlopen`/`dlsym` wrapper that fails gracefully.

The MIT licence text above applies to MacroVisionKit too.
