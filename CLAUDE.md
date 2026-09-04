# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fork of [mazurel/zed-ctags](https://github.com/mazurel/zed-ctags): a Zed editor extension that exposes Universal Ctags as an LSP server (`ctags-lsp`, from [netmute/ctags-lsp](https://github.com/netmute/ctags-lsp)). It is customized for local Windows use with Pascal support.

## Commands

```sh
# Build the extension (WASM component — plain `cargo build` is NOT the deployable artifact)
cargo component build --release --target wasm32-wasip1

# Format check (enforced in CI)
cargo fmt -- --check
```

Prerequisites: `rustup target add wasm32-wasip1` and `cargo install cargo-component --locked`.

There are no tests. CI (`.github/workflows/build-local-extension.yml`) builds the wasm, packages `dist/ctags/` (extension.toml + extension.wasm + `server/ctags-lsp.exe` + a generated `install.ps1`), and uploads it as an artifact. Installing locally = download artifact → run `install.ps1` → restart Zed. It copies to `%LOCALAPPDATA%\Zed\extensions\installed\ctags` and drops the server binary into `%LOCALAPPDATA%\Zed\extensions\work\ctags\ctags-lsp-project\`.

## Architecture

Two halves, deliberately decoupled:

1. **Extension (Rust → wasm), `src/`** — tiny and meant to stay that way. `lib.rs` implements `zed::Extension::language_server_command`; `ctags_lsp.rs` computes the binary path and args. It does **not** download anything: it requires a pre-built binary at `ctags-lsp-project/ctags-lsp.exe` (relative to the extension's work dir) and fails with an install-status error if missing. It launches the server with `--ctags-bin <path>`, where the ctags binary comes from the `CTAGS_BIN` env var or defaults to `D:\Tools\ctags\ctags.exe` on Windows. Enabled languages are declared in `extension.toml` (C, C++, Python, Pascal).

2. **Server binary (Go), `server/ctags-lsp.exe`** — a prebuilt, *patched* build of netmute/ctags-lsp committed directly to the repo. Patches live in `.github/patches/` (e.g. `ctags-lsp-windows-file-uri.patch` fixes Windows drive-letter file URIs, `/C:/...` → `C:/...`); further server changes (like the Pascal declaration→implementation lookup) are rebuilt from the patched Go source out-of-tree and the new exe is committed. The Rust side never builds this binary.

Consequences for changes:
- Rust changes require rebuilding the wasm component and reinstalling; they are invisible to Zed until then.
- Never regenerate `server/ctags-lsp.exe` from an upstream release — it must be the patched build.
- `extension.toml` version and the packaged artifact must stay consistent when bumping.
