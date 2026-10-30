;;; init.el --- Portable Emacs setup (Ubuntu + Windows) with Clojure/CIDER  -*- lexical-binding: t; -*-

;;; OS detection

(defconst my/windows-p (eq system-type 'windows-nt))
(defconst my/linux-p   (eq system-type 'gnu/linux))

;;; Packages
;; Packages are not committed (elpa/ is gitignored); each machine installs
;; its own on first launch.

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

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

;;; Sensible UI defaults

(setq inhibit-startup-screen t
      make-backup-files nil
      custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))
(show-paren-mode 1)
(put 'upcase-region 'disabled nil)
(put 'dired-find-alternate-file 'disabled nil)

;;; Cross-platform file handling
;; LF everywhere so files stay clean in git; still read CRLF files fine.

(prefer-coding-system 'utf-8-unix)
(setq-default buffer-file-coding-system 'utf-8-unix)

;;; OS-specific settings

(when my/windows-p
  (setq default-directory "~/"
        w32-use-native-image-API t
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
