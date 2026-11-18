;;; zed_test.el --- Tests for zed.el -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;
;;   emacs -Q --batch -L . -l zed_test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'zed)
(require 'compile)

;;;; Helpers

(defmacro zed-test--with-buffer (content &rest body)
  "Insert CONTENT in a `zed-mode' buffer, fontify it, and run BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((zed-eglot-auto-start nil))
       (insert ,content)
       (zed-mode)
       (font-lock-ensure)
       (goto-char (point-min))
       ,@body)))

(defun zed-test--faces (text &optional nth)
  "Return the list of faces covering the NTH occurrence of TEXT.
NTH is 1-based and defaults to 1.  Each character's face is
normalised to a list, and the result is the de-duplicated union,
so a single face over the whole of TEXT gives a one-element list."
  (save-excursion
    (goto-char (point-min))
    (unless (search-forward text nil t (or nth 1))
      (error "Text %S (occurrence %s) not found" text (or nth 1)))
    (let ((faces '()))
      (dotimes (i (length text))
        (let ((f (get-text-property (+ (match-beginning 0) i) 'face)))
          (dolist (face (if (listp f) f (list f)))
            (cl-pushnew face faces))))
      (nreverse faces))))

(defun zed-test--face (text &optional nth)
  "Return the single face covering the NTH occurrence of TEXT.
Fails the test if TEXT is covered by more than one face."
  (let ((faces (zed-test--faces text nth)))
    (should (= (length faces) 1))
    (car faces)))

;;;; Font lock: definitions

(ert-deftest zed-test-definition-plain ()
  (zed-test--with-buffer "definition user {}\n"
    (should (eq (zed-test--face "definition") 'font-lock-keyword-face))
    (should (eq (zed-test--face "user") 'font-lock-type-face))))

(ert-deftest zed-test-definition-prefixed ()
  (zed-test--with-buffer "definition entra/group {}\n"
    (should (eq (zed-test--face "entra/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "group") 'font-lock-type-face))))

(ert-deftest zed-test-definition-nested-prefix ()
  (zed-test--with-buffer "definition a/b/user {}\n"
    (should (eq (zed-test--face "a/b/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "user") 'font-lock-type-face))))

(ert-deftest zed-test-partial-prefixed ()
  (zed-test--with-buffer "partial org/common {}\n"
    (should (eq (zed-test--face "partial") 'font-lock-keyword-face))
    (should (eq (zed-test--face "org/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "common") 'font-lock-type-face))))

(ert-deftest zed-test-prefix-face-differs-from-default ()
  "The prefix face must not look like plain text."
  (should-not (eq (face-attribute 'zed-type-prefix-face :inherit) 'default))
  (should (face-attribute 'zed-type-prefix-face :inherit)))

;;;; Font lock: relations and permissions

(ert-deftest zed-test-relation-subject-types ()
  (zed-test--with-buffer
      "definition doc {\n  relation viewer: entra/user | group#member | user:*\n}\n"
    (should (eq (zed-test--face "relation") 'font-lock-keyword-face))
    (should (eq (zed-test--face "viewer") 'font-lock-variable-name-face))
    (should (eq (zed-test--face "entra/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "user") 'font-lock-type-face))
    (should (eq (zed-test--face "group") 'font-lock-type-face))
    (should (eq (zed-test--face "member") 'font-lock-constant-face))
    (should (eq (zed-test--face "*") 'font-lock-constant-face))))

(ert-deftest zed-test-permission ()
  (zed-test--with-buffer
      "definition doc {\n  permission view = viewer + owner->view\n}\n"
    (should (eq (zed-test--face "permission") 'font-lock-keyword-face))
    (should (eq (zed-test--face "view") 'font-lock-function-name-face))
    (should (eq (zed-test--face "->") 'font-lock-builtin-face))))

(ert-deftest zed-test-arrow-functions ()
  (zed-test--with-buffer
      "definition doc {\n  permission view = group.all(member) + team.any(member)\n}\n"
    (should (eq (zed-test--face "all") 'font-lock-builtin-face))
    (should (eq (zed-test--face "any") 'font-lock-builtin-face))))

;;;; Font lock: caveats

(ert-deftest zed-test-caveat-name-prefixed ()
  (zed-test--with-buffer
      "caveat entra/has_group(required_group string, token_groups list<string>) {\n  required_group in token_groups\n}\n"
    (should (eq (zed-test--face "caveat") 'font-lock-keyword-face))
    (should (eq (zed-test--face "entra/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "has_group") 'font-lock-function-name-face))))

(ert-deftest zed-test-caveat-parameters ()
  (zed-test--with-buffer
      "caveat entra/has_group(required_group string, token_groups list<string>) {\n  required_group in token_groups\n}\n"
    (should (eq (zed-test--face "required_group") 'zed-caveat-parameter-face))
    (should (eq (zed-test--face "token_groups") 'zed-caveat-parameter-face))
    (should (eq (zed-test--face "string") 'font-lock-type-face))
    (should (eq (zed-test--face "list") 'font-lock-type-face))
    ;; Uses in the body are not declarations.
    (should-not (memq 'zed-caveat-parameter-face
                      (zed-test--faces "required_group" 2)))
    (should-not (memq 'zed-caveat-parameter-face
                      (zed-test--faces "token_groups" 2)))))

(ert-deftest zed-test-caveat-parameters-multiline ()
  (zed-test--with-buffer
      "caveat limits(\n  amount int,\n  allowed map<bool>\n) {\n  amount > 1\n}\n"
    (should (eq (zed-test--face "limits") 'font-lock-function-name-face))
    (should (eq (zed-test--face "amount") 'zed-caveat-parameter-face))
    (should (eq (zed-test--face "allowed") 'zed-caveat-parameter-face))
    (should (eq (zed-test--face "int") 'font-lock-type-face))
    (should-not (memq 'zed-caveat-parameter-face
                      (zed-test--faces "amount" 2)))))

(ert-deftest zed-test-with-caveat-reference ()
  (zed-test--with-buffer
      "definition doc {\n  relation a: user with entra/has_group\n  relation b: user with plain_caveat\n}\n"
    (should (eq (zed-test--face "with") 'font-lock-keyword-face))
    (should (eq (zed-test--face "entra/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "has_group") 'font-lock-function-name-face))
    (should (eq (zed-test--face "plain_caveat") 'font-lock-function-name-face))))

(ert-deftest zed-test-with-expiration ()
  (zed-test--with-buffer
      "use expiration\ndefinition doc {\n  relation a: user with expiration\n  relation b: user with a/cav and expiration\n}\n"
    (should (eq (zed-test--face "expiration" 1) 'font-lock-builtin-face))
    (should (eq (zed-test--face "expiration" 2) 'font-lock-builtin-face))
    (should (eq (zed-test--face "expiration" 3) 'font-lock-builtin-face))
    (should (eq (zed-test--face "a/") 'zed-type-prefix-face))
    (should (eq (zed-test--face "cav") 'font-lock-function-name-face))))

;;;; Font lock: comments

(ert-deftest zed-test-comments ()
  (zed-test--with-buffer
      "// definition foo\n/* relation bar */\ndefinition user {}\n"
    (should (memq 'font-lock-comment-face (zed-test--faces "foo")))
    (should (memq 'font-lock-comment-face (zed-test--faces "bar")))
    (should (eq (zed-test--face "user") 'font-lock-type-face))))

;;;; Indentation

(ert-deftest zed-test-indentation ()
  (zed-test--with-buffer
      "definition doc {\nrelation viewer: user\npermission view = viewer + (\nviewer\n)\n}\n"
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat "definition doc {\n"
                           "  relation viewer: user\n"
                           "  permission view = viewer + (\n"
                           "    viewer\n"
                           "  )\n"
                           "}\n")))))

(ert-deftest zed-test-indentation-offset ()
  (let ((zed-indent-offset 4))
    (zed-test--with-buffer "definition doc {\nrelation viewer: user\n}\n"
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string)
                     "definition doc {\n    relation viewer: user\n}\n")))))

(ert-deftest zed-test-indentation-skips-block-comments ()
  (zed-test--with-buffer "/*\n   keep me\n*/\n"
    (forward-line 1)
    (zed-indent-line)
    (should (equal (buffer-string) "/*\n   keep me\n*/\n"))))

;;;; Validation

(ert-deftest zed-test-validation-target ()
  (let ((dir (make-temp-file "zed-test" t)))
    (unwind-protect
        (let ((schema (expand-file-name "schema.zed" dir)))
          (write-region "" nil schema)
          (should (equal (zed--validation-target schema) schema))
          (write-region "" nil (expand-file-name "schema.yml" dir))
          (should (equal (zed--validation-target schema)
                         (expand-file-name "schema.yml" dir)))
          ;; .yaml takes precedence over .yml.
          (write-region "" nil (expand-file-name "schema.yaml" dir))
          (should (equal (zed--validation-target schema)
                         (expand-file-name "schema.yaml" dir))))
      (delete-directory dir t))))

(ert-deftest zed-test-compilation-error-regexp ()
  (let* ((entry (cdr (assq 'zed compilation-error-regexp-alist-alist)))
         (line "error: parse error in `schema.zed`, line 3, column 20: oops"))
    (should entry)
    (should (memq 'zed compilation-error-regexp-alist))
    (should (string-match (car entry) line))
    (should (equal (match-string (nth 1 entry) line) "schema.zed"))
    (should (equal (match-string (nth 2 entry) line) "3"))
    (should (equal (match-string (nth 3 entry) line) "20"))))

;;;; Mode setup

(ert-deftest zed-test-auto-mode ()
  (should (eq (assoc-default "foo.zed" auto-mode-alist #'string-match)
              'zed-mode)))

(ert-deftest zed-test-keymap ()
  (should (eq (lookup-key zed-mode-map (kbd "C-c C-c")) #'zed-validate)))

(ert-deftest zed-test-comment-settings ()
  (zed-test--with-buffer ""
    (should (equal comment-start "// "))
    (should (equal comment-end ""))))

(provide 'zed_test)
;;; zed_test.el ends here
