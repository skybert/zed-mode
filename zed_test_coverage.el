;;; zed_test_coverage.el --- Code coverage for the zed-mode tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Used by `make coverage'.  Not part of the package.
;;
;; 1. Load this file before the tests and call `zed-coverage-start'.
;;    It instruments zed.el and zed-tuples.el with undercover.el,
;;    which writes a SimpleCov JSON report when Emacs exits.
;;
;; 2. In a fresh Emacs, call `zed-coverage-check'.  It prints the
;;    coverage per file and exits non-zero if the total is below the
;;    percentage in the baseline file.
;;
;; Dependencies are installed from MELPA into `zed-coverage-deps-dir'.

;;; Code:

(require 'package)
(require 'json)
(require 'seq)

(defvar undercover-force-coverage)

(defvar zed-coverage-deps-dir (expand-file-name ".deps")
  "Directory the coverage dependencies are installed into.")

(defvar zed-coverage-report-file (expand-file-name "coverage.json")
  "SimpleCov JSON report written by undercover.")

(defvar zed-coverage-baseline-file (expand-file-name ".coverage-baseline")
  "File holding the minimum accepted coverage percentage.")

(defvar zed-coverage-files '("zed.el" "zed-tuples.el")
  "Source files to measure.")

(defun zed-coverage--ensure-undercover ()
  "Install undercover.el into `zed-coverage-deps-dir' if missing."
  (setq package-user-dir zed-coverage-deps-dir)
  (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
  (package-initialize)
  (unless (package-installed-p 'undercover)
    (package-refresh-contents)
    (package-install 'undercover)))

(defun zed-coverage-start ()
  "Instrument `zed-coverage-files'.  Call before loading them."
  (zed-coverage--ensure-undercover)
  (require 'undercover)
  (when (file-exists-p zed-coverage-report-file)
    (delete-file zed-coverage-report-file))
  ;; undercover only measures on CI by default.
  (setq undercover-force-coverage t)
  (eval `(undercover ,@zed-coverage-files
                     (:report-format 'simplecov)
                     (:report-file ,zed-coverage-report-file)
                     (:send-report nil))
        t))

(defun zed-coverage--read-report ()
  "Return a list of (FILE RELEVANT COVERED) from the report."
  (unless (file-exists-p zed-coverage-report-file)
    (error "No coverage report %s; run the tests first"
           zed-coverage-report-file))
  (let* ((json-array-type 'list)
         (json-key-type 'string)
         (report (json-read-file zed-coverage-report-file))
         (coverage (cdr (assoc "coverage" (cdar report)))))
    (mapcar (lambda (entry)
              (let ((lines (delq nil (copy-sequence (cdr entry)))))
                (list (file-name-nondirectory (car entry))
                      (length lines)
                      (seq-count (lambda (n) (> n 0)) lines))))
            coverage)))

(defun zed-coverage-check ()
  "Print coverage and exit non-zero if it is below the baseline."
  (let* ((files (zed-coverage--read-report))
         (relevant (apply #'+ (mapcar #'cadr files)))
         (covered (apply #'+ (mapcar #'caddr files)))
         (percent (/ (* 100.0 covered) (max relevant 1)))
         (baseline (with-temp-buffer
                     (insert-file-contents zed-coverage-baseline-file)
                     (string-to-number (buffer-string)))))
    (dolist (f files)
      (princ (format "%-16s %3d/%3d lines\n" (car f) (nth 2 f) (nth 1 f))))
    (princ (format "Total coverage: %.2f%% (baseline %.2f%%)\n"
                   percent baseline))
    (cond
     ;; Allow for rounding of the stored baseline.
     ((< percent (- baseline 0.005))
      (princ "FAIL: coverage went down.\n")
      (kill-emacs 1))
     ((> percent (+ baseline 0.005))
      (princ (format "Coverage went up; raise the baseline with:\n  echo %.2f > %s\n"
                     percent (file-name-nondirectory zed-coverage-baseline-file))))))
  (kill-emacs 0))

(provide 'zed_test_coverage)
;;; zed_test_coverage.el ends here
