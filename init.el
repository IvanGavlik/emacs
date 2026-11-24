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

;; Jump to definition (M-. / M-,) without a REPL, via clojure-lsp.
;; With a CIDER REPL connected, CIDER's xref backend takes over.
(use-package eglot
  :hook ((clojure-mode clojurescript-mode clojurec-mode) . eglot-ensure))

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
;; Copy mode: C-c C-t (freeze output) or C-c C-e (Emacs mode) -> select, M-w copies and STAYS in
;; copy mode (C-w still copies and exits to the terminal); C-c C-j goes back to the terminal.
(use-package ghostel
  :config
  (defun my/ghostel-copy-stay ()
    "Copy the region (soft wraps removed) and stay in copy mode, without moving point."
    (interactive)
    (when (use-region-p)
      (kill-ring-save (region-beginning) (region-end))
      (deactivate-mark)))
  (define-key ghostel-readonly-mode-map (kbd "M-w") #'my/ghostel-copy-stay))

;;; Sensible UI defaults

(setq inhibit-startup-screen t
      make-backup-files nil
      custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file) (load custom-file))
(show-paren-mode 1)
(global-display-line-numbers-mode 1) ; line numbers in every buffer
(tool-bar-mode -1)                   ; always hide the tool bar
;; Reload buffers when their file is changed on disk by another program
;; (e.g. Claude Code). Buffers with unsaved edits are never reverted.
(setq global-auto-revert-non-file-buffers t  ; also refresh Dired
      auto-revert-verbose nil)               ; no "Reverted buffer" message
(global-auto-revert-mode 1)

;; ediff-current-file may ask "Compare with auto-save file?"; the auto-save
;; file holds our own unsaved edits, so both sides look identical. Always
;; compare against the real file on disk instead.
(defvar my/ediff-saved-wincfg nil
  "Window layout from before `ediff-current-file', restored when Ediff quits.")

(defun my/ediff-restore-after-quit ()
  "After quitting Ediff: restore the previous layout, drop the FILE= buffer."
  (when my/ediff-saved-wincfg
    (set-window-configuration my/ediff-saved-wincfg)
    (setq my/ediff-saved-wincfg nil)
    (dolist (b (buffer-list))
      (when (string-prefix-p "FILE=" (buffer-name b))
        (kill-buffer b)))))
;; depth 90: run after ediff-cleanup-mess has killed the control buffer
(add-hook 'ediff-quit-hook #'my/ediff-restore-after-quit 90)

(defun my/ediff-current-file-vs-disk (orig-fn &rest args)
  (setq my/ediff-saved-wincfg (current-window-configuration))
  (cl-letf* ((orig-y-or-n-p (symbol-function 'y-or-n-p))
             ((symbol-function 'y-or-n-p)
              (lambda (prompt)
                (unless (string-match-p "auto-save" prompt)
                  (funcall orig-y-or-n-p prompt)))))
    (apply orig-fn args)))
(advice-add 'ediff-current-file :around #'my/ediff-current-file-vs-disk)

;; When saving a buffer whose file also changed on disk, Emacs asks
;; "...changed on disk; really edit the buffer?". Answering n aborts the
;; save (as before) and now also opens Ediff: buffer vs. disk version.
(defun my/ediff-on-supersession (orig-fn filename)
  (condition-case err
      (funcall orig-fn filename)
    (file-supersession
     ;; Only for the "n" answer; "r" (revert) signals "File reverted".
     (when (equal (cadr err) "File changed on disk")
       (let ((buf (current-buffer)))
         (run-at-time 0 nil
                      (lambda ()
                        (when (buffer-live-p buf)
                          (with-current-buffer buf (ediff-current-file)))))))
     (signal (car err) (cdr err)))))
(advice-add 'ask-user-about-supersession-threat
            :around #'my/ediff-on-supersession)

;; Same idea for C-x C-s: "FILE has changed since visited or saved.  Save
;; anyway?" -> answering no ("Save not confirmed") now opens Ediff too.
(defun my/ediff-on-save-refused (orig-fn &rest args)
  (let ((buf (current-buffer))
        (changed (and buffer-file-name
                      (buffer-modified-p)
                      (file-exists-p buffer-file-name)
                      (not (verify-visited-file-modtime (current-buffer))))))
    (condition-case err
        (apply orig-fn args)
      (user-error
       (when (and changed (equal (cadr err) "Save not confirmed"))
         (run-at-time 0 nil
                      (lambda ()
                        (when (buffer-live-p buf)
                          (with-current-buffer buf (ediff-current-file))))))
       (signal (car err) (cdr err))))))
(advice-add 'basic-save-buffer :around #'my/ediff-on-save-refused)
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

;;; Session restore (desktop-save-mode)
;; On exit, saves open files (with cursor positions), Dired buffers, tabs and
;; window layout; restores them on the next start. Autosaves every 30s too, so
;; a crash or Windows shutdown loses little. Shells, terminals and Magit buffers
;; are not restored. Stored per machine in desktop/ (gitignored).
;; M-x desktop-save = save now, M-x desktop-clear = close everything,
;; M-x desktop-remove = forget the session (next start is fresh).

(defconst my/desktop-dir
  (file-name-as-directory (expand-file-name "desktop" user-emacs-directory)))
(make-directory my/desktop-dir t)

(setq desktop-dirname             my/desktop-dir
      desktop-path                (list my/desktop-dir)
      desktop-save                t           ; save on exit without asking
      desktop-auto-save-timeout   30          ; seconds of idle between autosaves
      ;; After a crash the lock file stays behind; load anyway if the Emacs that
      ;; owned it is no longer running, ask only if it still is (a 2nd instance).
      desktop-load-locked-desktop 'check-pid
      ;; Create every buffer at startup (not lazily), so the windows in each
      ;; restored tab find their buffers (shells included) instead of *scratch*.
      desktop-restore-eager       t
      ;; Restore frames/tabs, but pull them back on screen if a monitor is gone.
      desktop-restore-frames      t
      desktop-restore-in-current-display t
      desktop-restore-forces-onscreen    t)

;; Shell buffers (M-x shell) have no file, so desktop skips them by default.
;; Save each shell's name and current directory; on restore start a fresh
;; shell with the same name in that directory (output/processes are not kept).
(defun my/desktop-shell-misc (_desktop-dirname)
  "Data desktop stores for a shell buffer: its current directory."
  default-directory)

(defun my/desktop-shell-enable ()
  (setq-local desktop-save-buffer #'my/desktop-shell-misc))
(add-hook 'shell-mode-hook #'my/desktop-shell-enable)

;; Exact directory tracking for M-x shell. By default Emacs guesses the
;; directory from the `cd' commands you type, which breaks on Git Bash paths
;; (/c/Users -> c:/c/Users), `cd -', pushd, aliases and scripts. Instead bash
;; reports its real directory after every command with an OSC 7 escape
;; sequence (via PROMPT_COMMAND), which Emacs reads into `default-directory'.
;; Git Bash: `pwd -W' gives C:/...; Linux: plain $PWD.
(defconst my/shell-osc7-prompt-command
  (concat "__emacs_d=$(pwd -W 2>/dev/null) && __emacs_d=/$__emacs_d"
          " || __emacs_d=$PWD;"
          " printf '\\e]7;file://%s%s\\e\\\\' \"$HOSTNAME\" \"$__emacs_d\""))

(define-advice shell (:around (orig &rest args) osc7-cwd)
  "Start shells with PROMPT_COMMAND reporting the directory via OSC 7."
  (let ((process-environment
         (cons (concat "PROMPT_COMMAND=" my/shell-osc7-prompt-command)
               process-environment)))
    (apply orig args)))

(defun my/shell-osc7-cwd (_ text)
  "Set `default-directory' from an OSC 7 file://HOST/PATH TEXT."
  (when (and (not (file-remote-p default-directory))
             (string-match "\\`file://[^/]*\\(/.*\\)\\'" text))
    (let ((dir (match-string 1 text)))
      (when (string-match-p "\\`/[A-Za-z]:/" dir) ; /C:/x -> C:/x (Windows)
        (setq dir (substring dir 1)))
      (when (file-directory-p dir)
        ;; Exact tracking works; stop guessing from typed `cd' commands.
        (when (bound-and-true-p shell-dirtrack-mode) (shell-dirtrack-mode -1))
        (cd-absolute dir)))))

(defun my/shell-osc7-enable ()
  (require 'ansi-osc)
  (setq-local ansi-osc-handlers
              (cons '("7" . my/shell-osc7-cwd)
                    (assoc-delete-all "7" (copy-sequence ansi-osc-handlers))))
  (add-hook 'comint-output-filter-functions #'comint-osc-process-output nil t))
(add-hook 'shell-mode-hook #'my/shell-osc7-enable)

(defun my/desktop-shell-restore (_file-name buffer-name misc)
  "Recreate a saved shell buffer BUFFER-NAME in directory MISC."
  (let ((default-directory (if (and (stringp misc) (file-directory-p misc))
                               misc
                             my/projects-dir)))
    (save-window-excursion (shell buffer-name))))

(with-eval-after-load 'desktop
  (add-to-list 'desktop-buffer-mode-handlers
               '(shell-mode . my/desktop-shell-restore)))

(desktop-save-mode 1)

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
