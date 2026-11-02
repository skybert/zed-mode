;;; zed.el --- Major mode for SpiceDB / zed schema files -*- lexical-binding: t; -*-

;; Keywords: languages, authzed, spicedb
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; `zed-mode' provides syntax highlighting and basic indentation for
;; SpiceDB schema files (.zed), and registers "spicedb lsp" as the
;; language server for eglot.
;;
;; Usage:
;;
;;   (add-to-list 'load-path "/path/to/dir/containing/zed.el")
;;   (require 'zed)
;;
;; Set `zed-eglot-auto-start' to nil if you do not want eglot to be
;; started automatically in .zed buffers.

;;; Code:

(require 'seq)

(defgroup zed nil
  "Major mode for SpiceDB schema (.zed) files."
  :group 'languages
  :prefix "zed-")

(defcustom zed-indent-offset 2
  "Number of columns to indent per nesting level in `zed-mode'."
  :type 'integer
  :safe #'integerp)

(defcustom zed-lsp-command '("spicedb" "lsp")
  "Command (program and arguments) used by eglot to start the SpiceDB LSP."
  :type '(repeat string))

(defcustom zed-eglot-auto-start t
  "When non-nil, run `eglot-ensure' when entering `zed-mode'."
  :type 'boolean)

(defcustom zed-validate-command '("zed" "validate")
  "Command (program and arguments) used by `zed-validate'.
The file name is appended as the last argument."
  :type '(repeat string))

;;;; Syntax

(defconst zed--identifier-re "[a-zA-Z_][a-zA-Z0-9_]*"
  "Regexp matching a plain identifier.")

(defconst zed--type-re
  (concat zed--identifier-re "\\(?:/" zed--identifier-re "\\)*")
  "Regexp matching a (possibly namespace-prefixed) type name, e.g. org/user.")

(defconst zed--keywords
  '("definition" "caveat" "relation" "permission" "partial"
    "import" "use" "from" "with" "and" "self" "nil")
  "Keywords of the SpiceDB schema language.")

(defconst zed--caveat-types
  '("int" "uint" "bool" "string" "double" "bytes" "duration"
    "timestamp" "list" "map" "ipaddress" "any")
  "Parameter types allowed in caveat definitions.")

(defvar zed-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; C-style comments: // ... and /* ... */
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?{ "(}" st)
    (modify-syntax-entry ?} "){" st)
    (modify-syntax-entry ?\( "()" st)
    (modify-syntax-entry ?\) ")(" st)
    (modify-syntax-entry ?< "." st)
    (modify-syntax-entry ?> "." st)
    (dolist (c '(?+ ?- ?& ?| ?= ?: ?# ?. ?, ?! ?? ?%))
      (modify-syntax-entry c "." st))
    st)
  "Syntax table for `zed-mode'.")

(defconst zed-font-lock-keywords
  `(;; definition / caveat / partial names
    (,(concat "\\_<\\(definition\\|partial\\)\\_>[ \t]+\\(" zed--type-re "\\)")
     (2 font-lock-type-face))
    (,(concat "\\_<caveat\\_>[ \t]+\\(" zed--type-re "\\)")
     (1 font-lock-function-name-face))
    ;; relation / permission names
    (,(concat "\\_<relation\\_>[ \t]+\\(" zed--identifier-re "\\)")
     (1 font-lock-variable-name-face)
     ;; subject types following ':' and '|' on relation lines
     (,(concat "[:|][ \t]*\\(" zed--type-re "\\)")
      nil nil (1 font-lock-type-face)))
    (,(concat "\\_<permission\\_>[ \t]+\\(" zed--identifier-re "\\)")
     (1 font-lock-function-name-face))
    ;; keywords
    (,(regexp-opt zed--keywords 'symbols) . font-lock-keyword-face)
    ;; `with expiration'
    ("\\_<with\\_>[ \t]+\\(?:[^ \t\n]+[ \t]+and[ \t]+\\)?\\(expiration\\)\\_>"
     (1 font-lock-builtin-face))
    ("\\_<\\(?:and\\|use\\)[ \t]+\\(expiration\\)\\_>" (1 font-lock-builtin-face))
    ;; arrow functions: foo.all(bar) / foo.any(bar)
    ("\\.\\(all\\|any\\)[ \t]*(" (1 font-lock-builtin-face))
    ;; caveat parameter types (not when used as .any())
    (,(concat "\\(?:^\\|[^.]\\)" (regexp-opt zed--caveat-types 'symbols))
     (1 font-lock-type-face))
    ;; subject relation: group#member
    (,(concat "#\\(" zed--identifier-re "\\)") (1 font-lock-constant-face))
    ;; wildcard subject: user:*
    (":\\(\\*\\)" (1 font-lock-constant-face))
    ;; operators
    ("->" . font-lock-builtin-face))
  "Font-lock rules for `zed-mode'.")

;;;; Indentation

(defun zed-indent-line ()
  "Indent the current line according to brace/paren nesting."
  (interactive)
  (let* ((savep (> (current-column) (current-indentation)))
         (depth (save-excursion
                  (beginning-of-line)
                  (car (syntax-ppss))))
         (closing (save-excursion
                    (back-to-indentation)
                    (looking-at-p "[})]")))
         (indent (* zed-indent-offset
                    (max 0 (if closing (1- depth) depth)))))
    ;; Don't touch lines inside block comments or strings.
    (unless (save-excursion (beginning-of-line) (nth 8 (syntax-ppss)))
      (if savep
          (save-excursion (indent-line-to indent))
        (indent-line-to indent)))))

;;;; Validation

(defun zed--validation-target (file)
  "Return the file `zed validate' should be run on for FILE.
If a sibling FILE.yaml or FILE.yml exists, it is used, since such a
file loads the schema through `schemaFile:'.  Otherwise FILE itself."
  (let ((base (file-name-sans-extension file)))
    (or (seq-find #'file-exists-p
                  (list (concat base ".yaml") (concat base ".yml")))
        file)))

(defun zed-validate ()
  "Run `zed-validate-command' on the current file.
If the schema has a sibling .yaml/.yml validation file with the same
base name, that file is validated instead.  Offers to save the buffer
first if it has unsaved changes.  Output goes to a compilation buffer."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (when (and (buffer-modified-p)
             (y-or-n-p (format "Save %s first? " (buffer-name))))
    (save-buffer))
  (let ((target (zed--validation-target buffer-file-name)))
    (compile (mapconcat #'shell-quote-argument
                        (append zed-validate-command
                                (list (file-local-name target)))
                        " "))))

(with-eval-after-load 'compile
  (defvar compilation-error-regexp-alist)
  (defvar compilation-error-regexp-alist-alist)
  ;; error: parse error in `schema.zed`, line 3, column 20: ...
  (add-to-list 'compilation-error-regexp-alist-alist
               '(zed "in `\\([^`\n]+\\.\\(?:zed\\|ya?ml\\)\\)`, line \\([0-9]+\\), column \\([0-9]+\\)"
                     1 2 3))
  (add-to-list 'compilation-error-regexp-alist 'zed))

(defvar zed-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'zed-validate)
    map)
  "Keymap for `zed-mode'.")

;;;; Mode

;;;###autoload
(define-derived-mode zed-mode prog-mode "Zed"
  "Major mode for editing SpiceDB schema (.zed) files."
  :syntax-table zed-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "\\(?://+\\|/\\*+\\)[ \t]*")
  (setq-local font-lock-defaults '(zed-font-lock-keywords))
  (setq-local indent-line-function #'zed-indent-line)
  (setq-local electric-indent-chars
              (append '(?} ?\)) electric-indent-chars))
  (when (and zed-eglot-auto-start (fboundp 'eglot-ensure))
    (eglot-ensure)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.zed\\'" . zed-mode))

;;;; Eglot

(with-eval-after-load 'eglot
  (defvar eglot-server-programs)
  (add-to-list 'eglot-server-programs
               `(zed-mode . ,(lambda (&optional _interactive)
                               zed-lsp-command))))

(provide 'zed)
;;; zed.el ends here
