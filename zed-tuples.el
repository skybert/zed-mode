;;; zed-tuples.el --- Highlight SpiceDB relationship tuples -*- lexical-binding: t; -*-

;; Keywords: languages, authzed, spicedb
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; `zed-tuples-mode' is a minor mode that adds syntax highlighting of
;; SpiceDB / zed relationship tuples to any buffer, e.g. the
;; `relationships:' and assertion blocks of a `zed validate' YAML
;; file.
;;
;; A tuple looks like:
;;
;;   resource_type:resource_id#relation@subject_type:subject_id[#subject_relation]
;;
;; optionally followed by a caveat and/or an expiration:
;;
;;   company:fellowship#member@company_user:frodo-fellowship
;;   company_user:sam#delegated_agent@agent:sam-agent[within_limit:{"limit":5000}]
;;   doc:readme#viewer@user:gandalf[expiration:2026-01-01T00:00:00Z]
;;
;; Usage:
;;
;;   (require 'zed-tuples)
;;   (add-hook 'yaml-mode-hook #'zed-tuples-mode)
;;
;; or toggle it with M-x zed-tuples-mode.

;;; Code:

(defgroup zed-tuples nil
  "Highlighting of SpiceDB relationship tuples."
  :group 'zed
  :prefix "zed-tuples-")

;;;; Faces

(defface zed-tuples-type-face
  '((t :inherit font-lock-type-face))
  "Face for object types in tuples, e.g. `company' in `company:fellowship'.")

(defface zed-tuples-id-face
  '((t :inherit font-lock-constant-face))
  "Face for object IDs in tuples, e.g. `fellowship' in `company:fellowship'.")

(defface zed-tuples-relation-face
  '((t :inherit font-lock-variable-name-face))
  "Face for relations in tuples, e.g. `member' in `#member'.")

(defface zed-tuples-caveat-face
  '((t :inherit font-lock-function-name-face))
  "Face for caveat names in tuples, e.g. `within_limit'.")

(defface zed-tuples-caveat-context-face
  '((t :inherit font-lock-string-face))
  "Face for caveat context / expiration values in tuples.")

;;;; Regexps

(defconst zed-tuples--type-re
  "[a-zA-Z][a-zA-Z0-9_]*\\(?:/[a-zA-Z][a-zA-Z0-9_]*\\)*"
  "Regexp matching an object type, optionally namespaced: org/user.")

(defconst zed-tuples--id-re
  "\\(?:[a-zA-Z0-9/_|=+-]+\\|\\*\\)"
  "Regexp matching an object ID, or the `*' wildcard.")

(defconst zed-tuples--relation-re
  "[a-zA-Z_][a-zA-Z0-9_]*"
  "Regexp matching a relation name.")

(defconst zed-tuples--tuple-re
  (concat "\\_<"
          ;; 1, 2: resource
          "\\(" zed-tuples--type-re "\\):\\(" zed-tuples--id-re "\\)"
          ;; 3: relation
          "#\\(" zed-tuples--relation-re "\\)"
          ;; 4, 5: subject
          "@\\(" zed-tuples--type-re "\\):\\(" zed-tuples--id-re "\\)"
          ;; 6: optional subject relation (may be `...')
          "\\(?:#\\(" zed-tuples--relation-re "\\|\\.\\.\\.\\)\\)?")
  "Regexp matching a relationship tuple, without caveat/expiration.")

(defconst zed-tuples--suffix-re
  (concat "\\=\\[\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
          "\\(?::\\({.*?}\\|[^]\n]*\\)\\)?\\]")
  "Regexp matching a `[caveat:{...}]' or `[expiration:...]' block.
Must start right at point; may be repeated.")

(defconst zed-tuples-font-lock-keywords
  `((,zed-tuples--tuple-re
     (1 'zed-tuples-type-face t)
     (2 'zed-tuples-id-face t)
     (3 'zed-tuples-relation-face t)
     (4 'zed-tuples-type-face t)
     (5 'zed-tuples-id-face t)
     (6 'zed-tuples-relation-face t t)
     ;; Caveat and expiration blocks directly following the tuple.
     (,zed-tuples--suffix-re
      nil nil
      (1 'zed-tuples-caveat-face t)
      (2 'zed-tuples-caveat-context-face t t))))
  "Font-lock rules for `zed-tuples-mode'.
Faces override existing ones, since tuples often live inside YAML
strings or block scalars.")

;;;; Mode

;;;###autoload
(define-minor-mode zed-tuples-mode
  "Minor mode highlighting SpiceDB relationship tuples.
Useful in e.g. `yaml-mode' buffers holding `zed validate' files."
  :lighter " ZedT"
  (if zed-tuples-mode
      (font-lock-add-keywords nil zed-tuples-font-lock-keywords 'append)
    (font-lock-remove-keywords nil zed-tuples-font-lock-keywords))
  (when font-lock-mode
    (font-lock-flush)))

(provide 'zed-tuples)
;;; zed-tuples.el ends here
