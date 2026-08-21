# telegrama

A fast, low-memory native Telegram client for Linux.

GTK4 / libadwaita in Vala, talking to [TDLib](https://core.telegram.org/tdlib) over its C JSON
interface. Built because a Chromium-based client has no business using 600 MB to show text.

**Status:** in development. Chat list, history, sending, replies, edits, mentions, media
previews, notifications and a tray icon all work. See [docs/PLAN.md](docs/PLAN.md) for scope.

## Build

Requires Vala 0.56+, GTK4, libadwaita, blueprint-compiler, json-glib, meson, and TDLib
(AUR: `telegram-tdlib`). You will also need your own `api_id` / `api_hash` from
[my.telegram.org](https://my.telegram.org).

```sh
meson setup build -Dapi_id=... -Dapi_hash=...
ninja -C build
```

## Install

On Arch, from the packaging directory:

```sh
cd packaging/arch
TELEGRAMA_API_ID=... TELEGRAMA_API_HASH=... makepkg -si
```

`makepkg` clones the repository itself, so it packages what is on `main` rather than your
working tree. The credentials are compiled in, which is why they come from the environment
rather than the PKGBUILD — a package built with yours should not be passed on to anyone else.

## License

GPL-3.0-or-later
