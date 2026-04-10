# mORMot2 Extensions

Finally going to share a small collection of tools and libraries built with the mORMot2 framework. Most, if not all, are written purely with it. That means if you are interested in using them in your own Pascal codebase, adopting mORMot2 is required.

## Scope
- Utilities and helpers written in mormot2 (no external dependencies).
- Experimental ideas and reusable building blocks for mormot-based projects.
- Almost all of them are currently used in professional projects and many hobby projects not disclosed.

## Available extensions
- [mormot.ext.mcp](./mormot-mcp-server): build your MCP servers using mormot2 with no external deps or components.  
- [mormot.ext.winsparkle](./mormot-winsparkle): a pure mormot2 wrapper for [WinSparkle](https://github.com/vslavik/winsparkle), an app update framework (Windows-only) - supports silent install.
- [mormot.ext.otp](./mormot-otp): a single-unit RFC 4226/6238-compatible HOTP/TOTP (HMAC-SHA1 profile).
- [mormot.ext.markdown](./mormot-markdown): a single-unit Markdown to HTML processor with Daring Fireball, TxtMark, CommonMark, GitHub (GFM) dialects.
- [mormot.ext.os](./mormot-os): small `mormot.core.os` extension that add interactive bidirectional stdin/stdout pipes with child processes.

## Upcoming
- `mormot2-sockify`, a WebSocket to TCP proxy/bridge like the well-known websockify.
- Telegram API and bot framework.
- HTTP OAuth2, CSP/CORS units.
- An implementation of Google Firebase Cloud Messaging to distribute push notifications without external dependencies on Android and iOS devices.


## License
Refer to mORMot licenses.
