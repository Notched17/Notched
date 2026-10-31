# Activity API

Scripts and apps you trust can show **activities**, **banners** and **approval requests** in the Notched island. It is a small HTTP API on `127.0.0.1` with a token for each client. It is off until you turn on **Settings ▸ Modules ▸ Activity API**, and there is no listening socket while that module is off.

Design and security reasoning: [ADR-0021](adr/0021-activity-api-security.md).

## Set up

1. Turn on the **Activity API** module.
2. In its pane, press **New Client…**, give it a name and the scopes it needs, and copy the token. It is shown once; Notched keeps only a hash.
3. Note the port shown in the pane (random at first, then stable; you can change it).

```sh
export NOTCHED_PORT=50123          # the port in Settings
export NOTCHED_TOKEN=ntch_…        # the token you copied
```

Every request needs:

| Header | Value |
|---|---|
| `Authorization` | `Bearer $NOTCHED_TOKEN` |
| `Content-Type` | `application/json` (for `PUT` and `POST`) |
| `Host` | `127.0.0.1:<port>` or `localhost:<port>` (curl does this for you) |

Requests with an `Origin` or `Sec-Fetch-*` header (anything from a web page) are refused, so a page in your browser can't use the API.

## Scopes

| Scope | Allows |
|---|---|
| `activity` | `PUT`, `DELETE` and `GET` under `/v1/activities` |
| `banner` | `POST /v1/banners` |
| `approval` | `POST /v1/approvals` |

## Post or update an activity

`PUT /v1/activities/{id}`. The id is 1–64 characters of letters, digits, `.`, `-` and `_`. It belongs to your client, so two clients can both use `build`. Posting the same id again updates the activity in place.

```sh
curl -X PUT "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" \
  -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" \
  -d '{"template":"progress","title":"Build","subtitle":"Compiling","progress":0.4,"symbol":"hammer.fill","tint":"orange"}'
```

| Field | Type | Notes |
|---|---|---|
| `template` | `"status"`, `"progress"`, `"countdown"` | required |
| `title` | string | required, up to 40 characters |
| `subtitle` | string | up to 80 |
| `symbol` | string | an SF Symbol name such as `bolt.fill`; an unknown name falls back to a default |
| `tint` | string | `white` (default), `blue`, `green`, `orange`, `red`, `yellow`, `purple`, `pink`, `teal`, `gray` |
| `progress` | number | required for `progress`; clamped to 0…1 |
| `endsAt` | ISO 8601 date | required for `countdown`; 1 second to 24 hours from now |
| `trailing` | string | status only: short text beside the notch, up to 8 characters |
| `openURL` | string | `http` or `https` only; opened when you click it |
| `alert` | bool | expand the island briefly. At most once per 30 s per client; extra alerts post as plain updates |
| `kind` | `"live"` (default), `"passive"` | `passive` ranks lower. An API activity can never be a system one |
| `staleAfter` | seconds, 10…14400 | default 600; the activity looks outdated until updated |
| `expiresAfter` | seconds, 60…28800 | default 3600; it ends if not updated by then |

Answers: `201 {"id":"build","state":"active"}` when created, `200` when updated.

What you see: **status** shows the symbol (and `trailing`), **progress** a ring (and a bar when expanded), **countdown** a ticking timer. The expanded view always says "from <your client's name>", so an activity can't pass itself off as the system. All text is shown as plain text; nothing is read as markup.

At most **5** live activities per client (a sixth gets `409 too_many_activities`).

## End, list

```sh
curl -X DELETE "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" -H "Authorization: Bearer $NOTCHED_TOKEN"
curl -X DELETE "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build?dismiss=immediate" -H "Authorization: Bearer $NOTCHED_TOKEN"   # skip "Recent"
curl "http://127.0.0.1:$NOTCHED_PORT/v1/activities" -H "Authorization: Bearer $NOTCHED_TOKEN"
```

`DELETE` answers `204`, or `404` if there was no such activity.

## Banners

A short banner for a one-off event. At most 10 a minute per client.

```sh
curl -X POST "http://127.0.0.1:$NOTCHED_PORT/v1/banners" \
  -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Deploy done","subtitle":"prod","symbol":"checkmark.circle.fill","tint":"green"}'
```

`title` up to 24 characters, `subtitle` up to 16. Answer: `202 {"queued":true}`.

### Banner links

`notched://banner?title=Done&symbol=checkmark&tint=green` shows a banner marked "via link". Links carry no token (any app or web page can open one), so they are off unless **Allow banners from notched:// links** is on, at most one per 2 s and five a minute. They can only show a banner. Timers: `notched://timer?minutes=10&label=Tea`.

## Ask for approval

`POST /v1/approvals` shows **Allow / Deny** in the island and **waits** for your answer.

```sh
curl -X POST "http://127.0.0.1:$NOTCHED_PORT/v1/approvals" \
  -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Deploy to prod?","detail":"main @ 3f2a9c1","options":["allow","deny"],"timeout":60}'
# → {"decision":"allow"}
```

`decision` is `allow`, `deny`, `timeout` (nobody answered; `timeout` is 5–120 s, default 60) or `dismissed` (the client hung up, the client was revoked, or the module was turned off). One open request per client (`409 approval_pending`).

## Errors

Always JSON: `{"error":{"code":"invalid_payload","message":"progress is required for the progress template.","field":"progress"}}`.

| Status | `code` | Meaning |
|---|---|---|
| 400 | `invalid_json`, `invalid_payload`, `bad_request`, `unsupported` | the body or request couldn't be used; `field` names the problem |
| 401 | `missing_token`, `invalid_token` | send `Authorization: Bearer <token>`; the same answer for unknown and revoked tokens |
| 403 | `missing_scope`, `browser_forbidden` | the client lacks the scope; or a web page sent the request |
| 404 | `not_found` | no such endpoint or activity |
| 405 | `method_not_allowed` | including `OPTIONS` (there is no CORS) |
| 409 | `too_many_activities`, `approval_pending` | |
| 411, 413, 415 | `length_required`, `too_large`, `unsupported_media_type` | bodies are up to 16 KB with a `Content-Length` |
| 421 | `bad_host` | the `Host` header isn't `127.0.0.1:<port>` or `localhost:<port>` |
| 429 | `rate_limited` | 10 requests a second per client (burst 20); `Retry-After` says when. 20 bad tokens in a minute pause further bad tokens (valid tokens keep working) |
| 503 | `disabled` | the module was turned off |

## Examples

### Shell: wrap a long command

```sh
notched-run() {   # usage: notched-run "Backup" rsync -a ~/Documents /Volumes/Backup
  local title="$1"; shift
  local url="http://127.0.0.1:$NOTCHED_PORT/v1/activities/run-$$"
  local auth=(-H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json")
  curl -s -X PUT "$url" "${auth[@]}" -d "{\"template\":\"status\",\"title\":\"$title\",\"symbol\":\"gearshape.fill\",\"tint\":\"blue\"}" >/dev/null
  "$@"; local code=$?
  curl -s -X DELETE "$url" "${auth[@]}" >/dev/null
  curl -s -X POST "http://127.0.0.1:$NOTCHED_PORT/v1/banners" "${auth[@]}" \
    -d "{\"title\":\"$title\",\"subtitle\":\"$([ $code = 0 ] && echo done || echo failed)\",\"symbol\":\"$([ $code = 0 ] && echo checkmark.circle.fill || echo xmark.circle.fill)\"}" >/dev/null
  return $code
}
```

### Raycast script command

```sh
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Focus 25 minutes
# @raycast.mode silent
# @raycast.icon 🍅
END=$(date -u -v+25M +%Y-%m-%dT%H:%M:%SZ)
curl -s -X PUT "http://127.0.0.1:$NOTCHED_PORT/v1/activities/focus" \
  -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" \
  -d "{\"template\":\"countdown\",\"title\":\"Focus\",\"endsAt\":\"$END\",\"symbol\":\"brain.head.profile\",\"tint\":\"purple\",\"alert\":true}" > /dev/null
```

Keep the token in Raycast's script-command environment, not in the script file.

### Shortcuts

Add a **Get Contents of URL** action:

- URL `http://127.0.0.1:50123/v1/banners` (your port)
- Method `POST`
- Headers `Authorization` = `Bearer ntch_…`, `Content-Type` = `application/json`
- Request Body `JSON`: `title` (Text) = `Laundry done`, `symbol` (Text) = `washer.fill`

## Claude Code

Claude Code's hooks use the same server through the `notched-hook` helper and a private internal client. See [ADR-0022](adr/0022-claude-code-hook-protocol.md).
