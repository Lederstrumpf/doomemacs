;;; doom.el --- the heart of the beast -*- lexical-binding: t; -*-
;;
;; Author:  Henrik Lissner <contact@henrik.io>
;; URL:     https://github.com/doomemacs/doomemacs
;;
;;   =================     ===============     ===============   ========  ========
;;   \\ . . . . . . .\\   //. . . . . . .\\   //. . . . . . .\\  \\. . .\\// . . //
;;   ||. . ._____. . .|| ||. . ._____. . .|| ||. . ._____. . .|| || . . .\/ . . .||
;;   || . .||   ||. . || || . .||   ||. . || || . .||   ||. . || ||. . . . . . . ||
;;   ||. . ||   || . .|| ||. . ||   || . .|| ||. . ||   || . .|| || . | . . . . .||
;;   || . .||   ||. _-|| ||-_ .||   ||. . || || . .||   ||. _-|| ||-_.|\ . . . . ||
;;   ||. . ||   ||-'  || ||  `-||   || . .|| ||. . ||   ||-'  || ||  `|\_ . .|. .||
;;   || . _||   ||    || ||    ||   ||_ . || || . _||   ||    || ||   |\ `-_/| . ||
;;   ||_-' ||  .|/    || ||    \|.  || `-_|| ||_-' ||  .|/    || ||   | \  / |-_.||
;;   ||    ||_-'      || ||      `-_||    || ||    ||_-'      || ||   | \  / |  `||
;;   ||    `'         || ||         `'    || ||    `'         || ||   | \  / |   ||
;;   ||            .===' `===.         .==='.`===.         .===' /==. |  \/  |   ||
;;   ||         .=='   \_|-_ `===. .==='   _|_   `===. .===' _-|/   `==  \/  |   ||
;;   ||      .=='    _-'    `-_  `='    _-'   `-_    `='  _-'   `-_  /|  \/  |   ||
;;   ||   .=='    _-'          '-__\._-'         '-_./__-'         `' |. /|  |   ||
;;   ||.=='    _-'                                                     `' |  /==.||
;;   =='    _-'                                                            \/   `==
;;   \   _-'                                                                `-_   /
;;    `''                                                                      ``'
;;
;; These demons are not part of GNU Emacs.
;;
;;; Commentary:
;;
;; This is Doom's heart, where I define all its major constants and variables,
;; set its saner global defaults, then prepare Emacs to bootstrap Doom.
;;
;; The overall load order of Doom is as follows:
;;
;;   $EMACSDIR/early-init.el
;;   $EMACSDIR/lisp/doom.el
;;   $EMACSDIR/lisp/doom-start.el
;;   $DOOMDIR/init.el
;;   `doom-before-modules-init-hook'
;;   {$DOOMDIR,~/.emacs.d}/modules/*/*/init.el
;;   `doom-after-modules-init-hook'
;;   `doom-before-modules-config-hook'
;;   {$DOOMDIR,~/.emacs.d}/modules/*/*/config.el
;;   `doom-after-modules-config-hook'
;;   $DOOMDIR/config.el
;;   `after-init-hook'
;;   `emacs-startup-hook'
;;   `doom-init-ui-hook'
;;   `window-setup-hook'
;;
;;; Code:

(eval-and-compile  ; Check version at both compile and runtime.
  ;; Doom's minimum supported version of Emacs is 27.1. Its my goal to support
  ;; one major version below the stable release, for about a year or until
  ;; stable is ubiquitous (or at least easily accessible) across Linux distros.
  (when (< emacs-major-version 27)
    (user-error
     (concat
      "Detected Emacs " emacs-version ", but Doom requires 27.1 or newer.\n\n"
      "The version of Emacs in use is located at:\n\n  " (car command-line-args) "\n\n"
      "A guide for installing a newer version of Emacs can be found at:\n\n  "
      (format "https://docs.doomemacs.org/-/install/%s"
              (cond ((eq system-type 'darwin) "on-macos")
                    ((memq system-type '(cygwin windows-nt ms-dos)) "on-windows")
                    ("on-linux")))
      "\n\n"
      (if (not noninteractive)
          (concat "If you believe this error is a mistake, run 'doom doctor' on the command line\n"
                  "to diagnose common issues with your config and system.")
        (concat "Alternatively, either update your $PATH environment variable to include the\n"
                "path of the desired Emacs executable OR alter the $EMACS environment variable\n"
                "to specify the exact path or command needed to invoke Emacs. For example:\n\n"
                (let ((command (ignore-errors (file-name-nondirectory (cadr (member "--load" command-line-args))))))
                  (concat "  $ EMACS=/path/to/valid/emacs " command " ...\n"
                          "  $ EMACS=\"/Applications/Emacs.app/Contents/MacOS/Emacs\" " command " ...\n"
                          "  $ EMACS=\"snap run emacs\" " command " ...\n"))
                "\nAborting..."))))))

;; Doom needs to be synced/rebuilt if either Doom or Emacs has been
;; up/downgraded. This is because byte-code isn't backwards compatible, and many
;; packages (including Doom), make in absolute paths into their caches that need
;; to be refreshed.
(let ((old-version (eval-when-compile emacs-version)))
  (unless (equal emacs-version old-version)
    (user-error (concat "Doom was compiled with Emacs %s, but was loaded with %s. Run 'doom sync' to"
                        "recompile it.")
                emacs-version old-version)))

;; Remember these variables' initial values, so we can safely reset them at a
;; later time, or consult them without fear of contamination.
(dolist (var '(exec-path load-path process-environment
               load-suffixes load-file-rep-suffixes
               file-name-handler-alist))
  (unless (get var 'initial-value)
    (put var 'initial-value (default-toplevel-value var))))

;; Since Emacs 27, package initialization occurs before `user-init-file' is
;; loaded, but after `early-init-file'. Doom handles package initialization, so
;; we must prevent Emacs from doing it again.
(setq package-enable-at-startup nil)


;;
;;; Startup optimizations

;; Here are Doom's hackiest (and least offensive) startup optimizations. They
;; exploit implementation details and unintended side-effects, and will  change
;; often between major Emacs releases. I've (roughly) ordered them from most to
;; least effective (on Linux), and disable them if this is a daemon session
;; (where startup time matters less) or in debug-mode (to mitigate interference
;; with our debugging).
(unless (or (daemonp) init-file-debug)
  ;; PERF: `file-name-handler-alist' is consulted on each call to `require',
  ;;   `load', or various file/io functions (like `expand-file-name' or
  ;;   `file-remote-p'). You get a noteable boost to startup time by unsetting
  ;;   or simplifying its value.
  (let ((old-value (get 'file-name-handler-alist 'initial-value)))
    (setq file-name-handler-alist
          ;; HACK: If the bundled elisp for this Emacs install isn't
          ;;   byte-compiled (but is compressed), then leave the gzip file
          ;;   handler there so Emacs won't forget how to read read them.
          ;;
          ;;   calc-loaddefs.el is our heuristic for this because it is built-in
          ;;   to all supported versions of Emacs, and calc.el explicitly loads
          ;;   it uncompiled. This ensures that the only other, possible
          ;;   fallback would be calc-loaddefs.el.gz.
          (if (eval-when-compile
                (if (locate-file-internal "calc-loaddefs.el" load-path) t))
              nil
            (list (rassq 'jka-compr-handler old-value))))
    ;; Make sure the new value survives any current let-binding.
    (set-default-toplevel-value 'file-name-handler-alist file-name-handler-alist)
    ;; COMPAT: ...but restore `file-name-handler-alist' later, because it is
    ;;   needed for handling encrypted or compressed files, among other things.
    (defun doom-reset-file-handler-alist-h ()
      (setq file-name-handler-alist
            ;; Merge instead of overwrite because there may have been changes to
            ;; `file-name-handler-alist' since startup we want to preserve.
            (delete-dups (append file-name-handler-alist old-value))))
    (add-hook 'emacs-startup-hook #'doom-reset-file-handler-alist-h 101))

  (unless noninteractive
    ;; PERF: Resizing the Emacs frame (to accommodate fonts that are smaller or
    ;;   larger than the system font) appears to impact startup time
    ;;   dramatically. The larger the delta in font size, the greater the delay.
    ;;   Even trivial deltas can yield a ~1000ms loss, though it varies wildly
    ;;   depending on font size.
    (setq frame-inhibit-implied-resize t)

    ;; PERF: Emacs supports a "default init file", which is a library named
    ;;   "default.el" living anywhere in your `load-path' (or `$EMACSLOADPATH').
    ;;   It's loaded after $EMACSDIR/init.el, but there really is no reason to
    ;;   do so. Doom doesn't define one, users shouldn't use one, and it seems
    ;;   too magical when an explicit `-l FILE' would do. I do away with it for
    ;;   the *miniscule* savings in file IO spent trying to load it.
    (setq inhibit-default-init t)

    ;; PERF,UX: Reduce *Message* noise at startup. An empty scratch buffer (or
    ;;   the dashboard) is more than enough, and faster to display.
    (setq inhibit-startup-screen t
          inhibit-startup-echo-area-message user-login-name)
    ;; PERF,UX: Remove "For information about GNU Emacs..." message at startup.
    ;;   It's redundant with our dashboard and incurs a premature redraw.
    (advice-add #'display-startup-echo-area-message :override #'ignore)

    ;; PERF: Shave seconds off startup time by starting the scratch buffer in
    ;;   `fundamental-mode', rather than, say, `org-mode' or `text-mode', which
    ;;   pull in a ton of packages. `doom/open-scratch-buffer' provides a better
    ;;   scratch buffer anyway.
    (setq initial-major-mode 'fundamental-mode
          initial-scratch-message nil)

    ;; PERF: Inexplicably, `tty-run-terminal-initialization' can sometimes take
    ;;   2-3s when starting up Emacs in the terminal. Whatever slows it down at
    ;;   startup doesn't appear to affect it if it's called a little later in
    ;;   the startup process, so that's what I do.
    ;; REVIEW: This optimization is not understood. Investigate this properly!
    (advice-add #'tty-run-terminal-initialization :override #'ignore)
    (defun doom-init-tty-h ()
      (advice-remove #'tty-run-terminal-initialization #'ignore)
      (tty-run-terminal-initialization (selected-frame) nil t))
    (add-hook 'window-setup-hook #'doom-init-tty-h)

    ;; PERF,UX: Site files tend to use `load-file', which emits "Loading X..."
    ;;   messages in the echo area. Writing to the echo-area triggers a
    ;;   redisplay, which can be expensive during startup. This may also cause
    ;;   an flash of white when creating the first frame.
    (define-advice load-file (:override (file) silence)
      (load file nil 'nomessage))
    ;; COMPAT: But undo our `load-file' advice later, as to limit the scope of
    ;;   any edge cases it could induce.
    (define-advice startup--load-user-init-file (:before (&rest _) undo-silence)
      (advice-remove #'load-file #'load-file@silence))

    ;; PERF: `load-suffixes' and `load-file-rep-suffixes' are consulted on each
    ;;   `require' and `load'. Doom won't load any dmodules this early, so omit
    ;;   .so for a small startup boost. This is later restored in doom-start.
    (set-default-toplevel-value 'load-suffixes '(".elc" ".el"))
    (set-default-toplevel-value 'load-file-rep-suffixes '(""))

    ;; PERF: The mode-line procs a couple dozen times during startup. This is
    ;;   normally quite fast, but disabling the default mode-line and reducing the
    ;;   update delay timer seems to stave off ~30-50ms.
    (setq-default mode-line-format nil)
    (dolist (buf (buffer-list))
      (with-current-buffer buf (setq mode-line-format nil)))
    ;; PERF,UX: Premature redisplays can substantially affect startup times and
    ;;   produce ugly flashes of unstyled Emacs.
    (setq-default inhibit-redisplay t
                  inhibit-message t)
    ;; COMPAT: Then reset it with advice, because `startup--load-user-init-file'
    ;;   will never be interrupted by errors. And if these settings are left
    ;;   set, Emacs could appear frozen or garbled.
    (define-advice startup--load-user-init-file (:after (&rest _) undo-inhibit-vars)
      (setq-default inhibit-redisplay nil
                    inhibit-message nil)
      (unless (default-toplevel-value 'mode-line-format)
        (setq-default mode-line-format (get 'mode-line-format 'initial-value))))

    ;; PERF: Unset a non-trivial list of command line options that aren't
    ;;   relevant to our current OS, but `command-line-1' still processes.
    (unless IS-MAC
      (setq command-line-ns-option-alist nil))
    (when (or IS-MAC IS-WINDOWS)
      (setq command-line-x-option-alist nil))))


;;
;;; Core globals

(defgroup doom nil
  "An Emacs framework for the stubborn martian hacker."
  :link '(url-link "https://doomemacs.org"))

(defconst doom-version "3.0.0-dev"
  "Current version of Doom Emacs core.")

(defconst doom-modules-version "22.09.0-dev"
  "Current version of Doom Emacs.")

(defconst doom-profile
  (if-let (profile (getenv-internal "DOOMPROFILE"))
      ;; DEPRECATED Use `string-search' once 27 support is dropped
      (if (string-match-p "@" profile)
          profile
        (concat profile "@latest"))
    ;; TODO Restore this when profile system is complete
    ;; "default@latest"
    )
  "The name of the active profile.")

(defconst doom-emacs-dir user-emacs-directory
  "The path to the currently loaded .emacs.d directory. Must end with a slash.")

(defconst doom-core-dir (file-name-directory load-file-name)
  "The root directory of Doom's core files. Must end with a slash.")


;; DEPRECATED
(defconst IS-MAC      (eq system-type 'darwin))
(defconst IS-LINUX    (memq system-type '(gnu gnu/linux gnu/kfreebsd berkeley-unix)))
(defconst IS-WINDOWS  (memq system-type '(cygwin windows-nt ms-dos)))
(defconst IS-BSD      (memq system-type '(darwin berkeley-unix gnu/kfreebsd)))

(unless (featurep 'doom)
  ;; Since `system-configuration-features's docs state not to rely on it to test
  ;; for features, let's give users an easier way to detect them.
  (if (bound-and-true-p module-file-suffix)
      (push 'dynamic-modules features))
  (if (fboundp #'json-parse-string)
      (push 'jansson features))
  ;; `native-compile' exists whether or not it is functional (e.g. libgcc is
  ;; available or not). This seems silly, so pretend it doesn't exist if it
  ;; isn't available.
  (if (featurep 'native-compile)
      (if (not (native-comp-available-p))
          (delq 'native-compile features)))

  ;; DEPRECATED remove in v3
  (defconst EMACS28+    (> emacs-major-version 27))
  (defconst EMACS29+    (> emacs-major-version 28))
  ;; DEPRECATED remove in v3
  (defconst MODULES     (featurep 'dynamic-modules))
  (defconst NATIVECOMP  (featurep 'native-compile)))

;;; Custom error types
(define-error 'doom-error "An unexpected Doom error")
(define-error 'doom-core-error "Unexpected error in Doom's core" 'doom-error)
(define-error 'doom-hook-error "Error in a Doom startup hook" 'doom-error)
(define-error 'doom-autoload-error "Error in Doom's autoloads file" 'doom-error)
(define-error 'doom-user-error "Error caused by user's config or system" 'doom-error)
(define-error 'doom-module-error "Error in a Doom module" 'doom-error)
(define-error 'doom-package-error "Error with packages" 'doom-error)
(define-error 'doom-profile-error "Error while processing profiles" 'doom-error)

;;; Platform-specific fixes
;; Fix $HOME on Windows, where it's not normally defined, because many unix
;; tools expect it.
(when IS-WINDOWS
  (when-let (realhome
             (and (null (getenv-internal "HOME"))
                  (getenv "USERPROFILE")))
    (setenv "HOME" realhome)
    (setq abbreviated-home-dir nil)))

;;; Load Doom stdlib
;; Ensure Doom's core libraries are visible for loading
(add-to-list 'load-path doom-core-dir)
;; Load just the... bear necessities~
(require 'doom-lib)


;;
;;; File/directory variables

(defconst doom-modules-dir (expand-file-name "modules/" doom-emacs-dir)
  "The root directory for Doom's modules. Must end with a slash.")

(defconst doom-user-dir
  (expand-file-name
   (if-let (doomdir (getenv-internal "DOOMDIR"))
       (file-name-as-directory doomdir)
     (or (let ((xdgdir
                (file-name-concat
                 (or (getenv-internal "XDG_CONFIG_HOME")
                     "~/.config")
                 "doom/")))
           (if (file-directory-p xdgdir) xdgdir))
         "~/.doom.d/")))
  "Where your private configuration is placed.

Defaults to ~/.config/doom, ~/.doom.d or the value of the DOOMDIR envvar;
whichever is found first. Must end in a slash.")

;; TODO Use me
(defconst doom-profiles-file
  (expand-file-name "profiles.el" user-emacs-directory)
  "TODO")

(defconst doom-profiles-dir
  (if-let (profilesdir (getenv-internal "DOOMPROFILESDIR"))
      (expand-file-name "./" profilesdir)
    (expand-file-name "profiles/" doom-emacs-dir))
   "Where Doom stores its profiles.

Profiles are essentially snapshots of Doom Emacs environments. Every time you
update or sync, you create a new generation of a profile (which can be easily
rolled back or switched between with the DOOMPROFILE envvar). Must end in a
slash.")

(defconst doom-profile-dir
  (expand-file-name (concat (or doom-profile "default@latest") "/")
                    doom-profiles-dir)
  "The path to the current, active profile.

Must end in a slash.")

(defconst doom-profile-data-dir
  (expand-file-name "data/" doom-profile-dir)
  "Where file storage/servers for the current, active profile is kept.

Use this for long-living files that contain shared data that the user would
reasonably want to keep, and/or are required for Emacs to function correctly.
Must end in a slash.")

(defconst doom-profile-cache-dir
  (expand-file-name "cache/" doom-profile-dir)
  "Where file caches for the current, active profile is kept.

Use this for non-essential data files that, when deleted, won't cause breakage
or misbehavior, and can be restored. This includes server binaries or programs
downloaded/installed by packages. Must end in a slash.")

(defconst doom-profile-init-file
  (expand-file-name "init.el" doom-profile-dir)
  "TODO")


;;
;;; DEPRECATED file/directory vars

(defconst doom-local-dir
  (if-let (localdir (getenv-internal "DOOMLOCALDIR"))
      (expand-file-name (file-name-as-directory localdir))
    (if doom-profile
        doom-profile-dir
      (expand-file-name ".local/" doom-emacs-dir)))
  "Root directory for local storage.

Use this as a storage location for this system's installation of Doom Emacs.

These files should not be shared across systems. By default, it is used by
`doom-data-dir' and `doom-cache-dir'. Must end with a slash.")

(defconst doom-data-dir
  (if doom-profile
      doom-profile-data-dir
    (concat doom-local-dir "etc/"))
  "Directory for non-volatile local storage.

Use this for files that don't change much, like server binaries, external
dependencies or long-term shared data. Must end with a slash.")

(defconst doom-cache-dir
  (if doom-profile
      doom-profile-cache-dir
    (concat doom-local-dir "cache/"))
  "Directory for volatile local storage.

Use this for files that change often, like cache files. Must end with a slash.")

(defconst doom-autoloads-file
  (if doom-profile
      doom-profile-init-file
    (concat doom-local-dir "autoloads." emacs-version ".el"))
  "Where `doom-reload-core-autoloads' stores its core autoloads.

This file is responsible for informing Emacs where to find all of Doom's
autoloaded core functions (in lisp/lib/*.el).")

(defconst doom-env-file
  (file-name-concat (if doom-profile
                        doom-profile-dir
                      doom-local-dir)
                    "env")
  "The location of your envvar file, generated by `doom env`.

This file contains environment variables scraped from your shell environment,
which is loaded at startup (if it exists). This is helpful if Emacs can't
\(easily) be launched from the correct shell session (particularly for MacOS
users).")


;;
;;; Legacy support

(define-obsolete-variable-alias 'doom-private-dir 'doom-user-dir "3.0.0")
(define-obsolete-variable-alias 'doom-etc-dir 'doom-data-dir "3.0.0")

(make-obsolete-variable 'EMACS28+   "Use (>= emacs-major-version 28) instead" "3.0.0")
(make-obsolete-variable 'EMACS29+   "Use (>= emacs-major-version 29) instead" "3.0.0")
(make-obsolete-variable 'MODULES    "Use (featurep 'dynamic-modules) instead" "3.0.0")
(make-obsolete-variable 'NATIVECOMP "Use (featurep 'native-compile) instead" "3.0.0")


;;
;;; Native Compilation support (http://akrl.sdf.org/gccemacs.html)

(when (boundp 'native-comp-eln-load-path)
  ;; Don't store eln files in ~/.emacs.d/eln-cache (where they can easily be
  ;; deleted by 'doom upgrade').
  ;; REVIEW Use `startup-redirect-eln-cache' when 28 support is dropped
  (add-to-list 'native-comp-eln-load-path (expand-file-name "eln/" doom-cache-dir))

  ;; UX: Suppress compiler warnings and don't inundate users with their popups.
  ;;   They are rarely more than warnings, so are safe to ignore.
  (setq native-comp-async-report-warnings-errors init-file-debug
        native-comp-warning-on-missing-source init-file-debug))


;;
;;; Don't litter `doom-emacs-dir'/$HOME

;; HACK: I change `user-emacs-directory' because many packages (even built-in
;;   ones) abuse it to build paths for storage/cache files (instead of correctly
;;   using `locate-user-emacs-file'). This change ensures that said data files
;;   are never saved to the root of your emacs directory *and* saves us the
;;   trouble of setting a million directory/file variables. But it may throw off
;;   anyone (or any package) that uses it to search for your Emacs initfiles.
(setq user-emacs-directory doom-cache-dir)

;; ...However, this may surprise packages (and users) that read
;; `user-emacs-directory' expecting to find the location of your Emacs config,
;; such as server.el!
(setq server-auth-dir (file-name-concat doom-emacs-dir "server/"))

;; Packages with file/dir settings that don't use `user-emacs-directory' or
;; `locate-user-emacs-file' to initialize will need to set explicitly, to stop
;; them from littering in ~/.emacs.d/.
(setq desktop-dirname  (file-name-concat doom-cache-dir "desktop")
      pcache-directory (file-name-concat doom-cache-dir "pcache/"))

;; Allow the user to store custom.el-saved settings and themes in their Doom
;; config (e.g. ~/.doom.d/).
(setq custom-file (file-name-concat doom-user-dir "custom.el"))

;; By default, Emacs stores `authinfo' in $HOME and in plain-text. Let's not do
;; that, mkay? This file stores usernames, passwords, and other treasures for
;; the aspiring malicious third party. You'll need a GPG setup though.
(setq auth-sources (list (file-name-concat doom-data-dir "authinfo.gpg")
                         "~/.authinfo.gpg"))

(define-advice en/disable-command (:around (fn &rest args) write-to-data-dir)
  "Save safe-local-variables to `custom-file' instead of `user-init-file'.

Otherwise, `en/disable-command' (in novice.el.gz) is hardcoded to write them to
`user-init-file')."
  (let ((user-init-file custom-file))
    (apply fn args)))


;;
;;; Reasonable, global defaults

;;; Reduce unnecessary/unactionable warnings/logs
;; Disable warnings from the legacy advice API. They aren't actionable or
;; useful, and often come from third party packages.
(setq ad-redefinition-action 'accept)

;; Ignore warnings about "existing variables being aliased". Otherwise the user
;; gets very intrusive popup warnings about our (intentional) uses of
;; defvaralias, which are done because ensuring aliases are created before
;; packages are loaded is an unneeded and unhelpful maintenance burden. Emacs
;; still aliases them fine regardless.
(with-eval-after-load 'warnings
  (add-to-list 'warning-suppress-types '(defvaralias)))

;; Reduce debug output unless we've asked for it.
(setq debug-on-error init-file-debug
      jka-compr-verbose init-file-debug)

;;; Stricter security defaults
;; Emacs is essentially one huge security vulnerability, what with all the
;; dependencies it pulls in from all corners of the globe. Let's try to be a
;; *little* more discerning.
(setq gnutls-verify-error noninteractive
      gnutls-algorithm-priority
      (when (boundp 'libgnutls-version)
        (concat "SECURE128:+SECURE192:-VERS-ALL"
                (if (and (not IS-WINDOWS)
                         (>= libgnutls-version 30605))
                    ":+VERS-TLS1.3")
                ":+VERS-TLS1.2"))
      ;; `gnutls-min-prime-bits' is set based on recommendations from
      ;; https://www.keylength.com/en/4/
      gnutls-min-prime-bits 3072
      tls-checktrust gnutls-verify-error
      ;; Emacs is built with gnutls.el by default, so `tls-program' won't
      ;; typically be used, but in the odd case that it does, we ensure a more
      ;; secure default for it (falling back to `openssl' if absolutely
      ;; necessary). See https://redd.it/8sykl1 for details.
      tls-program '("openssl s_client -connect %h:%p -CAfile %t -nbio -no_ssl3 -no_tls1 -no_tls1_1 -ign_eof"
                    "gnutls-cli -p %p --dh-bits=3072 --ocsp --x509cafile=%t \
--strict-tofu --priority='SECURE192:+SECURE128:-VERS-ALL:+VERS-TLS1.2:+VERS-TLS1.3' %h"
                    ;; compatibility fallbacks
                    "gnutls-cli -p %p %h"))

(provide 'doom)
;;; doom.el ends here
