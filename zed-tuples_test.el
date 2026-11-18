;;; zed-tuples_test.el --- Tests for zed-tuples.el -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;
;;   emacs -Q --batch -L . -l zed-tuples_test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'zed-tuples)

;;;; Helpers

(defmacro zed-tuples-test--with-buffer (content &rest body)
  "Insert CONTENT in a buffer with `zed-tuples-mode', fontify, run BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,content)
     (fundamental-mode)
     (font-lock-mode 1)
     (zed-tuples-mode 1)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(defun zed-tuples-test--faces (text &optional nth)
  "Return the de-duplicated faces covering the NTH occurrence of TEXT.
NTH is 1-based and defaults to 1."
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

(defun zed-tuples-test--face (text &optional nth)
  "Return the single face covering the NTH occurrence of TEXT."
  (let ((faces (zed-tuples-test--faces text nth)))
    (should (= (length faces) 1))
    (car faces)))

;;;; Full tuples

(ert-deftest zed-tuples-test-basic ()
  (zed-tuples-test--with-buffer
      "company:fellowship#member@company_user:frodo-fellowship\n"
    (should (eq (zed-tuples-test--face "company") 'zed-tuples-type-face))
    (should (eq (zed-tuples-test--face "fellowship") 'zed-tuples-id-face))
    (should (eq (zed-tuples-test--face "member") 'zed-tuples-relation-face))
    (should (eq (zed-tuples-test--face "company_user") 'zed-tuples-type-face))
    (should (eq (zed-tuples-test--face "frodo-fellowship") 'zed-tuples-id-face))))

(ert-deftest zed-tuples-test-namespaced-types ()
  (zed-tuples-test--with-buffer "entra/group:admins#member@entra/user:alice\n"
    (should (eq (zed-tuples-test--face "entra/group") 'zed-tuples-type-face))
    (should (eq (zed-tuples-test--face "admins") 'zed-tuples-id-face))
    (should (eq (zed-tuples-test--face "entra/user") 'zed-tuples-type-face))
    (should (eq (zed-tuples-test--face "alice") 'zed-tuples-id-face))))

(ert-deftest zed-tuples-test-subject-relation ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@group:eng#member\n"
    (should (eq (zed-tuples-test--face "viewer") 'zed-tuples-relation-face))
    (should (eq (zed-tuples-test--face "eng") 'zed-tuples-id-face))
    (should (eq (zed-tuples-test--face "member") 'zed-tuples-relation-face))))

(ert-deftest zed-tuples-test-ellipsis-subject-relation ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@group:eng#...\n"
    (should (eq (zed-tuples-test--face "...") 'zed-tuples-relation-face))))

(ert-deftest zed-tuples-test-wildcard ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@user:*\n"
    (should (eq (zed-tuples-test--face "*") 'zed-tuples-id-face))))

;;;; Caveats and expiration

(ert-deftest zed-tuples-test-caveat ()
  (zed-tuples-test--with-buffer
      "company_user:sam#delegated_agent@agent:sam-agent[within_limit:{\"limit\":5000}]\n"
    (should (eq (zed-tuples-test--face "sam-agent") 'zed-tuples-id-face))
    (should (eq (zed-tuples-test--face "within_limit") 'zed-tuples-caveat-face))
    (should (eq (zed-tuples-test--face "{\"limit\":5000}")
                'zed-tuples-caveat-context-face))))

(ert-deftest zed-tuples-test-caveat-without-context ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@user:bob[is_weekday]\n"
    (should (eq (zed-tuples-test--face "is_weekday") 'zed-tuples-caveat-face))))

(ert-deftest zed-tuples-test-expiration ()
  (zed-tuples-test--with-buffer
      "doc:readme#viewer@user:gandalf[expiration:2026-01-01T00:00:00Z]\n"
    (should (eq (zed-tuples-test--face "gandalf") 'zed-tuples-id-face))
    (should (eq (zed-tuples-test--face "expiration") 'zed-tuples-caveat-face))
    (should (eq (zed-tuples-test--face "2026-01-01T00:00:00Z")
                'zed-tuples-caveat-context-face))))

(ert-deftest zed-tuples-test-caveat-and-expiration ()
  (zed-tuples-test--with-buffer
      "doc:readme#viewer@user:bob[ok:{\"a\":1}][expiration:2026-01-01T00:00:00Z]\n"
    (should (eq (zed-tuples-test--face "ok") 'zed-tuples-caveat-face))
    (should (eq (zed-tuples-test--face "expiration") 'zed-tuples-caveat-face))
    (should (eq (zed-tuples-test--face "2026-01-01T00:00:00Z")
                'zed-tuples-caveat-context-face))))

;;;; Partially typed tuples

(ert-deftest zed-tuples-test-partial-resource-only ()
  (zed-tuples-test--with-buffer "doc:readme\n"
    (should (eq (zed-tuples-test--face "doc") 'zed-tuples-type-face))
    (should (eq (zed-tuples-test--face "readme") 'zed-tuples-id-face))))

(ert-deftest zed-tuples-test-partial-with-relation ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@us\n"
    (should (eq (zed-tuples-test--face "viewer") 'zed-tuples-relation-face))
    (should (eq (zed-tuples-test--face "us") 'zed-tuples-type-face))))

(ert-deftest zed-tuples-test-unclosed-caveat ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@user:bob[within_limit:{\"a\":1}\n"
    (should (eq (zed-tuples-test--face "within_limit") 'zed-tuples-caveat-face))))

;;;; In context

(ert-deftest zed-tuples-test-in-yaml ()
  (zed-tuples-test--with-buffer
      "relationships: |-\n  doc:readme#viewer@user:bob\nassertions:\n  assertTrue:\n    - \"doc:readme#view@user:bob\"\n"
    (should (eq (zed-tuples-test--face "viewer") 'zed-tuples-relation-face))
    ;; 2nd occurrence of "view" is the relation in the assertion
    ;; (the 1st is inside "viewer").
    (should (eq (zed-tuples-test--face "view" 2) 'zed-tuples-relation-face))
    (should (eq (zed-tuples-test--face "bob" 2) 'zed-tuples-id-face))))

(ert-deftest zed-tuples-test-overrides-existing-faces ()
  "Tuples inside strings are still highlighted."
  (with-temp-buffer
    (insert "x = \"doc:readme#viewer@user:bob\"\n")
    (let ((st (make-syntax-table)))
      (modify-syntax-entry ?\" "\"" st)
      (set-syntax-table st))
    (font-lock-mode 1)
    (zed-tuples-mode 1)
    (font-lock-ensure)
    (should (eq (car (zed-tuples-test--faces "viewer"))
                'zed-tuples-relation-face))))

(ert-deftest zed-tuples-test-plain-text-untouched ()
  (zed-tuples-test--with-buffer "just some words here\n"
    (should (equal (zed-tuples-test--faces "just some words here") nil))))

;;;; Mode toggling

(ert-deftest zed-tuples-test-disable ()
  (zed-tuples-test--with-buffer "doc:readme#viewer@user:bob\n"
    (should (eq (zed-tuples-test--face "viewer") 'zed-tuples-relation-face))
    (zed-tuples-mode -1)
    (font-lock-ensure)
    (should-not zed-tuples-mode)
    (should (equal (zed-tuples-test--faces "viewer") nil))))

(provide 'zed-tuples_test)
;;; zed-tuples_test.el ends here
