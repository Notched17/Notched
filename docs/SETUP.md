# One-time setup (about 10 minutes, do this before running the first prompt)

Run the Terminal commands from inside the project folder:

```bash
cd "$HOME/Documents/Personal Projects/Notched"
```

## 1. Tools

1. **Xcode.** Install the latest version from the App Store, open it once, and accept the licence. Then check the command-line tools point at it:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version
   ```
2. **Signing certificate (free).** In Xcode, go to **Settings → Accounts**, click **+**, and add your Apple ID. A free "Personal Team" is enough. Select the team, click **Manage Certificates → + → Apple Development**. Claude Code will find this certificate. It stops macOS from forgetting the permissions you grant every time the app is rebuilt.
3. **Homebrew** (skip if `brew -v` already works). Install it from https://brew.sh, then:
   ```bash
   brew install xcodegen
   ```
4. **Node.js** is only needed for the skill installer: `brew install node`.

## 2. Let Claude Code see and build in Xcode

1. In **Xcode → Settings → Intelligence**, turn on the **MCP server** (Xcode 26.3 or later).
2. Register it with Claude Code:
   ```bash
   claude mcp add --transport stdio xcode -- xcrun mcpbridge
   ```
3. Grant **Terminal** (or iTerm, whichever you run Claude Code in) **Screen & System Audio Recording** in **System Settings → Privacy & Security**. Claude Code takes screenshots of the island to check its own design work, and needs this permission to do it.

## 3. Design and workflow skills

Inside the project folder:

```bash
# Apple Human Interface Guidelines skills. When asked, pick: hig-foundations,
# hig-platforms, hig-patterns and the hig-components-* skills
npx -y skills add raintree-technology/apple-hig-skills --agent claude-code
```

Then start Claude Code (`claude`) and run these slash commands:

```
/plugin marketplace add haider-nawaz/liquid-glass-skill
/plugin install liquid-glass@liquid-glass-skills
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

- **liquid-glass** covers the macOS 26+ Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, morphing with `glassEffectID`, glass buttons).
- **superpowers** gives Claude Code disciplined planning, test-driven development, systematic debugging and "verify before you say it's done" habits.

Quit Claude Code (`/exit`) and start it again so it loads the new MCP server, skills and plugins. Run `/mcp` and `/plugin` to check everything is listed.

## 4. Go

Start `claude` in the project folder, press **Shift+Tab** until it says **plan mode**, and paste the contents of `docs/prompts/M1-kickoff.md`.
