# ADR-0023: Claude Code usage from the session logs

- Status: accepted (M4a)
- Date: 2026-10-30

## Context

#62 shows today's and this week's token usage and an estimated cost, locally, with no login. The only source is Claude Code's session logs, an undocumented format.

## What the logs look like (Claude Code 2.1.312, a real session)

- `~/.claude/projects/<cwd with / → ->/<session-uuid>.jsonl`; subagents write `…/<session-uuid>/subagents/agent-<id>.jsonl`. `CLAUDE_CONFIG_DIR` and `~/.config/claude` can move them; both default locations are watched.
- Line types seen: `assistant`, `user`, `attachment`, `ai-title`, `last-prompt`, `queue-operation`, `tools-used`, `atis-latch`. Only `assistant` lines carry `message.usage`.
- `message.usage`: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`, plus extras we ignore.
- **One response is written as one line per content block with identical usage.** In a 13-response sample, 9 appeared on 2–3 lines. Counting lines would double or triple the totals.

## Decisions

- **Dedupe** by `message.id` + `requestId` (as ccusage does).
- **Tolerant parser** (`ClaudeUsageParser`): every field optional; non-numbers, negatives and booleans count as 0; huge numbers are capped; a missing 5m/1h split counts all cache writes as 5-minute; an unknown model is "unknown"; the synthetic `<synthetic>` model is skipped. Lines without `"output_tokens"` aren't decoded at all (cheap pre-filter). A line that fails is skipped, never fatal.
- **Local days.** Totals are bucketed by local calendar day and model. *Today* is the local day; *this week* is the last 7 days including today (Charlie's choice).
- **Prices** live in `claude-pricing.json` (bundled, overridable at `~/Library/Application Support/Notched/claude-pricing.json`): per million tokens, longest matching prefix wins. Input and output come from Anthropic's model table; cache prices use the standard multipliers except where a read price is published. Models with no price are shown as unpriced tokens, never as $0. Everything is labelled "≈ estimated at API prices" because a subscription isn't billed per token.
- **Incremental and lazy.** `ClaudeUsageService` remembers each file's inode and byte offset, reads only what was appended, parses only complete lines, and streams large files in 1 MB chunks. FSEvents (2 s latency) only marks the logs dirty; nothing is read until the AI tab is on screen (then at most once a second while it changes). With the tab closed and the module on, the cost is the FSEvents stream.
- **No credentials.** Plan-limit percentages are not attempted; no OAuth tokens are read or stored.

## Consequences

- Format changes show up as the "unreadable lines" count in the tab, not as crashes.
- Costs ignore server-side tools and batch/priority pricing.
