# Emacs config

Portable Emacs setup for Ubuntu and Windows (Clojure/CIDER, paredit, company, markdown).

## Install

**Ubuntu**
```bash
git clone git@github.com:IvanGavlik/emacs.git ~/.emacs.d
```

**Windows** (PowerShell) - Emacs reads `%APPDATA%\.emacs.d` unless `HOME` is set:
```powershell
git config --global core.autocrlf input
git clone git@github.com:IvanGavlik/emacs.git $env:APPDATA\.emacs.d
```

Start Emacs; packages install themselves on first launch (needs internet).

## Per-machine settings

Copy `local.el.example` to `local.el` (gitignored) for fonts, extra PATH entries and secrets.
`custom.el` (Customize output) is also gitignored.

## External tools

| Tool | Ubuntu | Windows |
|------|--------|---------|
| git, ripgrep, aspell | `apt install git ripgrep aspell` | `scoop install git ripgrep aspell` |
| Java + Clojure CLI / lein (CIDER) | `apt` / clojure.org | `scoop install openjdk clojure leiningen` |

If Emacs can't find a tool on Windows, add its directory to `my/extra-exec-paths` in `local.el`.

## Windows notes

- Use `/` in paths and `~` instead of hardcoded `C:/Users/...`.
- `.gitattributes` forces LF line endings; `utf-8-unix` is the default coding system.
- Native-comp-only or `vterm`-style packages are harder on native Windows; guard them with `(when my/linux-p ...)`.
- Alternative: run Emacs under WSL2 + WSLg and use the Ubuntu setup.
