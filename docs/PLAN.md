# telegrama — plan

A fast, low-memory native Telegram client for Linux. GTK4 + libadwaita, written in Vala,
talking to **TDLib** over its C JSON interface.

App ID `dev.miguel.Telegrama`, object path `/dev/miguel/Telegrama`, binary `telegrama`.

## Decisions (locked)

| | |
| --- | --- |
| **v1 scope** | Text-first. Chat list, read/send text, replies, edit, delete, read receipts, typing, notifications. Media = clickable placeholder → external viewer. |
| **UI model** | `AdwNavigationSplitView` — sidebar chat list + conversation pane, adaptive. |
| **Accounts** | Single account. |
| **TDLib** | System library from AUR `telegram-tdlib` (1.8.66). |

## Why TDLib and not our own MTProto

MTProto is a bespoke crypto protocol with DH key exchange, per-DC session state, seq/salt
management, file DC redirection, and an update-gap recovery algorithm that is genuinely subtle
(`pts`/`qts`/`date` reconciliation). TDLib is Telegram's own C++ implementation, ships a local
SQLite cache, and exposes everything through **five C functions**:

```c
int         td_create_client_id(void);
void        td_send(int client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);
void        td_set_log_message_callback(int max_verbosity, td_log_message_callback_ptr cb);
```

Requests and responses are JSON strings. That is a ~40-line VAPI, and json-glib does the rest.
Writing our own protocol layer would be months of work for a strictly worse result.

## Memory budget

The target is to beat a browser-based client by an order of magnitude, not to be the smallest
possible thing.

| | idle RSS |
| --- | --- |
| GTK4 + libadwaita shell | ~45–60 MB |
| TDLib (message DB enabled, medium account) | ~40–80 MB |
| **target total** | **< 150 MB** |

TDLib's own footprint scales with `use_message_database`. Keeping it on is the right trade —
it makes chat opening instant and cuts network chatter. If RSS becomes a problem, the knob is
TDLib's `optimize_memory_usage` / periodic `optimizeStorage`, not turning the DB off.

## Architecture

```
                 ┌──────────────────────── main thread ────────────────────────┐
                 │                                                              │
                 │   GTK4 / libadwaita widgets                                  │
                 │        ▲                    │                                │
                 │        │ GObject signals    │ Td.Client.request() async      │
                 │        │ + notify::props    ▼                                │
                 │   ┌────┴────────────────────────────┐                        │
                 │   │  models: ChatListModel,         │                        │
                 │   │  MessageListModel, UserStore    │                        │
                 │   └────▲────────────────────────────┘                        │
                 │        │ UpdateRouter dispatch                               │
                 │   ┌────┴────────────┐                                        │
                 │   │ Idle source     │◄──── AsyncQueue<Json.Node>             │
                 │   └─────────────────┘                                        │
                 └───────────────────────────────┬──────────────────────────────┘
                                                 │
                 ┌───────────────── receive thread ──────────────┐
                 │  loop { td_receive(1.0) → strdup → parse      │
                 │         → push to AsyncQueue → wake main }    │
                 └───────────────────────────────────────────────┘
                                                 │
                                          libtdjson.so
```

**Threading rule:** exactly one thread calls `td_receive`. `td_send` is safe from any thread but
we only call it from the main thread. `td_receive`'s returned string is valid only until that
thread's next call — copy it immediately.

**Parse on the worker thread**, not in the idle callback. A burst of updates on a large account
would otherwise jank the frame loop. The worker pushes owned `Json.Node`s into a
`GLib.AsyncQueue` and attaches a one-shot idle source; the idle handler drains the whole queue.

**Request/response** are matched by an `@extra` field we set on every outgoing request. A
`HashTable<string, SourceFunc>` resumes the waiting coroutine, so call sites read naturally:

```vala
var chat = yield client.request ("getChat", b => b.set_int_member ("chat_id", id));
```

## Module layout

Mirrors the `switchboard` conventions (meson + Blueprint + gresource).

```
telegrama/
├── meson.build
├── meson_options.txt            # api_id, api_hash
├── vapi/tdjson.vapi             # the 5 C functions
├── data/
│   ├── dev.miguel.Telegrama.desktop.in
│   ├── dev.miguel.Telegrama.metainfo.xml.in
│   ├── dev.miguel.Telegrama.gschema.xml
│   └── icons/
└── src/
    ├── main.vala  application.vala  config.vala.in  style.css
    ├── td/
    │   ├── client.vala           # thread pump, @extra futures, lifecycle
    │   ├── request.vala          # JSON builder helpers
    │   └── update-router.vala    # update @type → signal
    ├── model/
    │   ├── auth.vala             # authorization state machine
    │   ├── chat.vala             # GObject, notify props for bindings
    │   ├── chat-list-model.vala  # GLib.ListModel, ordered by chatPosition
    │   ├── message.vala
    │   ├── message-list-model.vala
    │   └── user-store.vala       # id → user/basicGroup/supergroup cache
    ├── ui/
    │   ├── window.blp/.vala
    │   ├── login-view.blp/.vala
    │   ├── chat-row.blp/.vala
    │   ├── chat-view.blp/.vala
    │   ├── message-row.blp/.vala
    │   └── composer.blp/.vala
    ├── util/
    │   ├── entities.vala         # formattedText → Pango markup
    │   └── time.vala
    └── notify/notifier.vala
```

## Phases

### Phase 0 — skeleton
Install AUR `telegram-tdlib`. Meson project, VAPI, `Td.Client` that starts the thread, sends
`getOption {name: "version"}`, prints the reply, shuts down cleanly. Proves the whole pipe end to end.

`meson_options.txt` carries `api_id` / `api_hash` — **we must register our own at
my.telegram.org**; shipping another client's credentials gets the app banned. They land in
`config.vala.in`.

### Phase 1 — auth
Drive the `updateAuthorizationState` machine:

```
WaitTdlibParameters → setTdlibParameters (flattened, incl. database_encryption_key)
WaitPhoneNumber     → setAuthenticationPhoneNumber
WaitCode            → checkAuthenticationCode
WaitPassword        → checkAuthenticationPassword     (2FA)
WaitRegistration    → registerUser                    (handle, don't design a flow)
Ready               → main window
```

`authorizationStateWaitEncryptionKey` no longer exists — since 1.8.6 the key is a parameter of
`setTdlibParameters`. Generate a random key on first run, store it in **libsecret** (0.21.7 is
installed), fall back to an empty key if the keyring is unavailable.

DB goes in `$XDG_DATA_HOME/telegrama`, files in `$XDG_CACHE_HOME/telegrama`.

`AdwCarousel`-free, single `AdwNavigationView` login flow: phone → code → password.

### Phase 2 — chat list
Call `loadChats {chat_list: chatListMain, limit: 30}` and build the list from the updates that
follow — `updateNewChat`, `updateChatPosition`, `updateChatLastMessage`, `updateChatReadInbox`.
`getChats` is not the right entry point; the ordered list is something we maintain ourselves.

Order comes from `chatPosition.order`, an **int64 that TDLib serializes as a JSON string**
(unlike `chat_id`/`message_id`, which are `int53` and safely fit in a JSON number). Parse it
with `int64.parse`. Sort descending, pinned first.

`Gtk.ListView` + `Gtk.SignalListItemFactory` + a `Gtk.SortListModel` over our store. Rows bind
to `Chat` GObject properties so updates repaint without rebuilding.

### Phase 3 — message history
The hard part. `getChatHistory {chat_id, from_message_id, offset, limit, only_local}`.

- First call with `only_local: true` commonly returns **zero** messages even when more exist —
  that is documented behavior, not an error. Retry with `only_local: false`.
- Newest at the bottom; scrolling up prepends older messages.

**Scroll anchoring is the top technical risk.** Prepending to the model while the user is
scrolled will jump the viewport. The fix: capture `vadjustment.upper - vadjustment.value`
before the splice and restore it after, in a single frame. Both Fractal and Paper Plane
converged on this; budget real time for getting it right.

**Text selection across messages is not possible in GTK4** without drawing the whole log
ourselves. Per-message `Gtk.Label` with `selectable: true` gives per-bubble selection. That is
the v1 answer; a custom-drawn log is a separate project.

### Phase 4 — rendering messages

Two jobs that turned out to be one phase: formatting the text people wrote, and rendering the
messages nobody wrote.

#### Text entities

`formattedText` is a plain string plus a flat list of `textEntity { offset, length, type }`.
TDLib defines 23 entity types. Converted to Pango markup in `util/entities.vala`.

**Entity offsets are in UTF-16 code units.** Vala strings are UTF-8 byte arrays, and the same
position in `"hi 👋 bold"` is 6 in UTF-16, 5 in codepoints and 8 in bytes. Convert once, at the
boundary, so nothing downstream ever sees a UTF-16 index — then unit-test it against
astral-plane text. This is the first thing in the project worth a test, and what finally gives
`meson test` something to run.

**Escape each run, not the whole string.** Escaping first would shift every byte offset you are
about to slice at, because `&` becomes `&amp;`.

**Split at entity boundaries** rather than assuming entities nest cleanly. Collect every start
and end, emit one run per gap, and open the tags that cover it.

Markup covers bold, italic, underline, strikethrough, code, pre, and text_url. Spoilers are
click-to-reveal: rendered with foreground and background both set to the label's own colour, so
they read as a solid bar and follow the theme without hardcoding one. Blockquotes and custom
emoji need real widget work and are not markup problems; they wait.

#### Service messages

Of TDLib's 104 `MessageContent` types, only about 23 are things a person wrote. The rest —
`ChatChangeTitle`, `ChatAddMembers`, `PinMessage`, `VideoChatStarted`, the whole gift and
giveaway family — are **service messages**, Telegram's term for system notices.

**TDLib does not flag them.** They arrive as ordinary messages whose content happens to be an
action type, with no boolean distinguishing them, so the list is hardcoded like every other
client does it.

They need different layout, not different styling: centered, no bubble, no avatar, dimmed. The
common ones get real sentences; the long tail falls back to a generic centered notice rather
than a bubble reading "Message".

### Phase 5 — sending and state
`sendMessage` with `inputMessageText`. Note the current signature takes `topic_id` and
`reply_to` — pass nulls for a plain send.

**Message IDs change after send.** The local echo gets a temporary id; `updateMessageSendSucceeded`
delivers `message` plus `old_message_id`. The list model must remap the row in place rather than
remove-and-insert, or the message visibly flickers.

Also handle `updateMessageContent` (edits), `updateDeleteMessages`, `updateMessageEdited`,
`updateChatReadOutbox` (✓✓), `updateChatAction` (typing indicator), `updateUserStatus` (online).

Mark read with `viewMessages` when rows actually enter the viewport — not on chat open. Getting
this right is a big part of the client feeling correct.

### Phase 6 — notifications and polish
`GNotification` via `GLib.Application.send_notification`, driven by TDLib's
`updateNotificationGroup` rather than raw `updateNewMessage` — TDLib already does the muting,
grouping and read-state logic, and reimplementing it produces phantom notifications.

Then: search (`searchChatsOnServer`), draft persistence via `updateChatDraftMessage`, window
state in GSettings, `--gapplication-service` for background operation, `style.css` pass.

## Known risks, ranked

1. **UTF-16 entity offsets** — silent corruption, easy to get wrong, affects every message.
2. **Scroll anchoring on prepend** — very visible, fiddly, no clean GTK4 API.
3. **TDLib build time** — the AUR package is a large C++ build. One-time, but budget 20–40 min.
4. **Update-storm jank** — mitigated by parsing off-thread; verify with a large account.
5. **Message id remapping** — cheap to get right if designed in, ugly to retrofit.

## Explicitly out of scope for v1

Stickers (needs an rlottie binding), animated emoji, reactions, voice/video calls, secret chats,
inline bots, polls, chat folders, multi-account, message forwarding UI, media upload.

Nothing here is architecturally excluded — the models are TDLib-shaped, so each is additive.
