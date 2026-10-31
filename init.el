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

;;; Tabs, shells and terminals (tmux replacement)
;; Tabs = tmux windows (C-x t 2 new, C-x t o next, C-x t r rename, C-x t 0 close).
;; Shells: C-u M-x shell to create named shells (*app-1*, *app-2*, ...).

(tab-bar-mode 1)

;; Shell buffers used for program output / logs
(setq comint-scroll-to-bottom-on-output 'others  ; auto-scroll unless you're reading it
      comint-buffer-maximum-size 20000)          ; cap log buffer size
(add-hook 'comint-output-filter-functions #'comint-truncate-buffer)

;; Full terminal emulator for TUI apps (Claude Code). Not supported on native Windows.
;; Copy mode: C-c C-e (Emacs mode) -> select, M-w -> C-c C-j back to terminal.
(when my/linux-p
  (use-package eat))

;;; Claude Code (print mode) with rendered Markdown answers
;; M-x my/claude        ask; the answer is appended to *claude*, rendered as Markdown
;; C-u M-x my/claude    continue the last conversation (claude -c)
;; Active region        the selected text is sent to Claude as input (like piping)
;; Runs in the folder of the current file / Dired / shell buffer; from any other
;; buffer (*scratch*, *Messages*, *claude*, ...) it runs in `my/projects-dir'.

(defun my/claude-directory ()
  "Folder Claude should run in for the current buffer."
  (if (or buffer-file-name (derived-mode-p 'dired-mode 'comint-mode))
      default-directory
    my/projects-dir))

(defun my/claude (prompt &optional continue)
  "Run `claude -p PROMPT' and show the answer as rendered Markdown in *claude*.
With prefix arg CONTINUE, continue the last conversation.  An active
region is sent to Claude on stdin."
  (interactive
   (list (read-string (if current-prefix-arg "Claude (continue): " "Claude: "))
         current-prefix-arg))
  (let* ((input (when (use-region-p)
                  (buffer-substring-no-properties (region-beginning) (region-end))))
         (dir (my/claude-directory))
         (default-directory dir)        ; claude process runs here
         (raw (generate-new-buffer " *claude-raw*"))
         (view (get-buffer-create "*claude*"))
         (start (with-current-buffer view
                  (unless (derived-mode-p 'gfm-view-mode) (gfm-view-mode))
                  (let ((inhibit-read-only t))
                    (goto-char (point-max))
                    (prog1 (point)
                      (insert "## " prompt "\n\n"
                              "`" (abbreviate-file-name dir) "`\n\n"
                              "_Thinking..._\n")))))
         (proc (make-process
                :name "claude"
                :buffer raw
                :command (append '("claude") (when continue '("-c")) (list "-p" prompt))
                :connection-type 'pipe
                :coding 'utf-8
                :noquery t
                :sentinel
                (lambda (p _event)
                  (unless (process-live-p p)
                    (let ((answer (with-current-buffer raw (buffer-string))))
                      (kill-buffer raw)
                      (with-current-buffer view
                        (let ((inhibit-read-only t))
                          (goto-char start)
                          (when (search-forward "_Thinking..._\n" nil t)
                            (replace-match ""))
                          (goto-char (point-max))
                          (insert answer "\n\n---\n\n")))
                      (dolist (w (get-buffer-window-list view nil t))
                        (set-window-point w start)
                        (set-window-start w start))
                      (message "Claude finished")))))))
    (when input (process-send-string proc input))
    (process-send-eof proc)
    (display-buffer view)
    (message "Claude is thinking...")))

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
