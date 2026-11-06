;;; init.el --- Portable Emacs setup (Ubuntu + Windows) with Clojure/CIDER  -*- lexical-binding: t; -*-

;;; OS detection

(defconst my/windows-p (eq system-type 'windows-nt))
(defconst my/linux-p   (eq system-type 'gnu/linux))

;; Where projects live: %USERPROFILE%\Projects on Windows ("~" there is %APPDATA%),
;; ~/Projects on Linux; falls back to the home folder if it doesn't exist.
(defconst my/projects-dir
  (let* ((home (if my/windows-p (getenv "USERPROFILE") "~"))
         (projects (expand-file-name "Projects" home)))
    (file-name-as-directory
     (expand-file-name (if (file-directory-p projects) projects home)))))

;;; Packages
;; Packages are not committed (elpa/ is gitignored); each machine installs
;; its own on first launch.

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; Git for Windows' MSYS gpg can't read "C:/..." paths, so GNU ELPA signature
;; checks fail ("Failed to download `gnu' archive"). Give it a "/c/..." path.
(when (and my/windows-p
           (string-match-p "/usr/bin/" (or (executable-find "gpg") "")))
  (setq package-gnupghome-dir
        (replace-regexp-in-string
         "\\`\\([A-Za-z]\\):"
         (lambda (m) (concat "/" (downcase (match-string 1 m))))
         (expand-file-name "elpa/gnupg" user-emacs-directory))))

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

;; The cached archive list goes stale and MELPA deletes old builds, so a new
;; package can fail with "Not found". On failure, refresh once and retry.
(define-advice package-install (:around (orig pkg &rest args) refresh-on-fail)
  (condition-case nil
      (apply orig pkg args)
    (error (package-refresh-contents)
           (apply orig pkg args))))

;; Built-in use-package (Emacs 29+) doesn't load :ensure support by default.
(require 'use-package-ensure)
(setq use-package-always-ensure t)

(use-package clojure-mode)

(use-package paredit
  :hook ((emacs-lisp-mode clojure-mode cider-repl-mode) . paredit-mode))

(use-package rainbow-delimiters
  :hook ((emacs-lisp-mode clojure-mode cider-repl-mode) . rainbow-delimiters-mode))

(use-package company
  :hook (after-init . global-company-mode))

(use-package cider
  :custom
  (cider-repl-display-help-banner nil)
  (cider-repl-pop-to-buffer-on-connect 'display-only)
  (cider-save-file-on-load t)
  (cider-show-error-buffer 'only-in-repl))

(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :hook (markdown-mode . visual-line-mode)
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-header-scaling t))

;;; Git
;; C-x g = status buffer (s stage, u unstage, c c commit, P p push, F p pull,
;; b b branch, l l log, z z stash, ? help). C-c C-c finishes a commit message.

(use-package magit
  :bind ("C-x g" . magit-status))

;;; Tabs, shells and terminals (tmux replacement)
;; Tabs = tmux windows (C-x t 2 new, C-x t o next, C-x t r rename, C-x t 0 close).
;; Shells: C-u M-x shell to create named shells (*app-1*, *app-2*, ...).

(tab-bar-mode 1)

;; Shell buffers used for program output / logs
(setq comint-scroll-to-bottom-on-output 'others  ; auto-scroll unless you're reading it
      comint-buffer-maximum-size 20000)          ; cap log buffer size
(add-hook 'comint-output-filter-functions #'comint-truncate-buffer)

;; Full terminal emulator for TUI apps (Claude Code), powered by libghostty-vt.
;; M-x ghostel; on first use it offers to download a prebuilt native module.
;; Copy mode: C-c C-t (freeze output) or C-c C-e (Emacs mode) -> select, M-w -> C-c C-j back to terminal.
(use-package ghostel)

;;; Sensible UI defaults

(setq inhibit-startup-screen t
      make-backup-files nil
      custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))
(show-paren-mode 1)
(put 'upcase-region 'disabled nil)
(put 'dired-find-alternate-file 'disabled nil)

;;; Active window indicator (mode line contrast)
;; The selected window gets a bright, bold mode line; the others fade out.
;; Re-applied after every theme change because themes reset face settings.

(defun my/apply-mode-line-contrast (&rest _)
  "Make `mode-line-active' stand out against `mode-line-inactive'."
  (let ((dark (eq (frame-parameter nil 'background-mode) 'dark)))
    (set-face-attribute 'mode-line-active nil
                        :background (if dark "#1f6feb" "#0b5fc4")
                        :foreground "#ffffff"
                        :weight 'bold
                        :box nil)
    (set-face-attribute 'mode-line-inactive nil
                        :background (if dark "#2a2a2a" "#e4e4e4")
                        :foreground (if dark "#777777" "#8a8a8a")
                        :weight 'normal
                        :box nil)))

(my/apply-mode-line-contrast)
(add-hook 'enable-theme-functions #'my/apply-mode-line-contrast)

;;; Cross-platform file handling
;; LF everywhere so files stay clean in git; still read CRLF files fine.

(prefer-coding-system 'utf-8-unix)
(setq-default buffer-file-coding-system 'utf-8-unix)

;;; OS-specific settings

(when my/windows-p
  ;; Start in the projects folder instead of %APPDATA% ("~").
  (setq default-directory my/projects-dir)
  (setq w32-use-native-image-API t
        ;; Avoid slow process spawning / stalls with many subprocesses (CIDER, git)
        w32-pipe-read-delay 0
        process-adaptive-read-buffering nil
        ;; Avoid TLS failures fetching from MELPA on some Windows builds
        gnutls-algorithm-priority "NORMAL:-VERS-TLS1.3"))

;; Tools Emacs shells out to (git, java, clojure/lein, rg, aspell).
;; On Windows install them with scoop/winget; on Linux apt provides them.
;; Extra directories that are not on Emacs' PATH go in local.el via `my/extra-exec-paths'.
(defvar my/extra-exec-paths nil
  "Directories to add to `exec-path' and PATH. Set in local.el per machine.")

(defvar my/local-file (expand-file-name "local.el" user-emacs-directory))
(when (file-exists-p my/local-file) (load my/local-file nil t))

(dolist (dir my/extra-exec-paths)
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir path-separator (getenv "PATH")))))

(setq ispell-program-name (or (executable-find "aspell")
                              (executable-find "hunspell")
                              "aspell"))

;; Optional: build with native compilation only where it is supported.
(when (and (fboundp 'native-comp-available-p) (not (native-comp-available-p)))
  (setq package-native-compile nil))

;;; init.el ends here
