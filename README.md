# telegram-native

A fast, low-memory native Telegram client for Linux.

GTK4 / libadwaita in Vala, talking to [TDLib](https://core.telegram.org/tdlib) over its C JSON
interface. Built because a Chromium-based client has no business using 600 MB to show text.

**Status:** planning. No code yet — see [docs/PLAN.md](docs/PLAN.md).

## Build

Requires Vala 0.56+, GTK4, libadwaita, blueprint-compiler, json-glib, meson, and TDLib
(AUR: `telegram-tdlib`). You will also need your own `api_id` / `api_hash` from
[my.telegram.org](https://my.telegram.org).

```sh
meson setup build -Dapi_id=... -Dapi_hash=...
ninja -C build
```

## License

GPL-3.0-or-later
