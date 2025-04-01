;;; feature-mode.el --- Major mode for editing Gherkin (i.e. Cucumber) user stories -*- lexical-binding: t -*-
;;; Version: 0.6.2
;;; Author: Michael Klishin
;;; Maintainer: Stéphane Maniaci
;;; URL: https://github.com/freesteph/cucumber.el
;;; Package-Requires: ((emacs "28.1"))

;; Copyright (C) 2008 — 2025 Michael Klishin and other contributors
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA 02110.
;;
;; Copy files to ~/.emacs.d/elisp/feature-mode and add this to your
;; .emacs to load the mode
;; (add-to-list 'load-path "~/.emacs.d/elisp/feature-mode")
;; ;; optional configurations
;; ;; default language if .feature doesn't have "# language: fi"
;; ;(setq feature-default-language "fi")
;; ;; and load it
;; (require 'feature-mode)
;; (add-to-list 'auto-mode-alist '("\.feature$" . feature-mode))
;;
;; If using RVM, set `feature-use-rvm' to `t' to enable RVM
;; support. This requires `rvm.el'.
;;
;; If using Chruby, set `feature-use-chruby' to `t' to enable
;; Chruby support. This requires `chruby.el'
;;
;; Language used in feature file is automatically detected from
;; "language: [2-letter ISO-code]" tag in feature file.  You can
;; choose the language feature-mode should use in case autodetection
;; fails.  Just add
;; (setq feature-default-language "en")
;; to your .emacs
;;
;; A copy of the Gherkin translations found at:
;;
;; https://github.com/cucumber/gherkin/blob/main/gherkin-languages.json
;;
;; is shipped with the repo to figure out translated keywords. Should
;; it fall out of date you can customise `feature-i18n-file' to point
;; at another JSON file.
;;
;; In order to get goto-step-definition to work, you must install the
;; ruby_parser gem:
;;
;;    gem install ruby_parser
;;
;; (be sure and use the ruby-interpreter that emacs will use based on
;; `exec-path')
;;
;;
;; Key Bindings
;; ------------
;;
;;  \C-c ,v
;;  :   Verify all scenarios in the current buffer file.
;;
;;  \C-c ,s
;;  :   Verify the scenario under the point in the current buffer.
;;
;;  \C-c ,f
;;  :   Verify all features in project. (Available in feature and
;;      ruby files)
;;
;;  \C-c ,r
;;  :   Repeat the last verification process.
;;
;;  \C-c ,g
;;  :   Go to step-definition under point

;;; Code:

(eval-when-compile (require 'cl-lib))

;;; Commentary:
;;
;; This package provides handling of feature files written using
;; Gherkin/Cucumber.  It provides font locking, indentation support
;; and can function in all the languages supported by Gherkin.
;;

(require 'thingatpt)
(require 'etags)
(require 'xref)
(require 'rx)

(defcustom feature-cucumber-command "cucumber {options} \"{feature}\""
  "Command used to run cucumber when there is no Rakefile."
  :group 'feature-mode
  :type 'string)

(defcustom feature-rake-command "rake cucumber CUCUMBER_OPTS=\"{options}\" FEATURE=\"{feature}\""
  "Command used to run cucumber when there is a Rakefile."
  :group 'feature-mode
  :type 'string)

(defcustom feature-enable-back-denting t
  "Makes subsequent pressing of the tab key back-dents the current line.
The line is back-dented by `feature-indent-offset' spaces."
  :type 'boolean
  :group 'feature-mode)

(defcustom feature-use-rvm nil
  "T when RVM is in use.  (Requires rvm.el)."
  :type 'boolean
  :group 'feature-mode)

(defcustom feature-use-chruby nil
  "T when Chruby is in use.  (Requires chruby.el)."
  :type 'boolean
  :group 'feature-mode)

(defcustom feature-root-marker-file-name "features"
  "File to look for to find the project root."
  :group 'feature-mode
  :type  'string)

(defcustom feature-align-steps-after-first-word nil
  "When set to t, make step lines align on the space after the first word."
  :type 'boolean
  :group 'feature-mode)

(defcustom feature-step-search-path "features/**/*steps.rb"
  "Path to project step definitions."
  :type 'string
  :group 'feature-mode)

(defcustom feature-step-search-gems-path "gems/ruby/*/gems/*/**/*steps.rb"
  "Path to find step definitions in installed gems."
  :type 'string
  :group 'feature-mode)

(defcustom feature-ruby-command "ruby"
  "Command to run ruby."
  :type 'string
  :group 'feature-mode)

;; Docker related
(defcustom feature-use-docker-compose t
  "Use `docker-compose' when docker-compose.yml exists in project."
  :type 'boolean
  :group 'feature-mode)

(defcustom feature-docker-compose-command "docker compose"
  "Command to run `docker-compose'."
  :type 'string
  :group 'feature-mode)

(defcustom feature-docker-compose-container "app"
  "The container to run cucumber in."
  :type 'string
  :group 'feature-mode)

(defgroup feature-mode nil
  "Major mode for editing feature (Cucumber/Gherkin) files."
  :group 'faces)

;;
;; Externals
;;

(declare-function rvm-activate-corresponding-ruby "ext:rvm.el")
(declare-function chruby-use-corresponding "ext:chruby.el")
(declare-function turn-on-orgtbl "ext:org-table.el")

;;
;; Keywords and font locking
;;

(when (featurep 'font-lock)
  (or (boundp 'font-lock-variable-name-face)
      (setq font-lock-variable-name-face font-lock-type-face)))

(defconst feature-mode--keywords
  '(feature background scenario scenario_outline given when then but and examples rule))

(defvar feature-default-language "en")
(defvar feature-default-directory "features")
(defvar feature-i18n-file (expand-file-name (concat (file-name-directory load-file-name) "/gherkin-languages.json")))

(defun feature-load-gherkin-i10n (filepath)
  "Read and parse Gherkin translations from the file at FILEPATH."
    (with-temp-buffer
      (insert-file-contents filepath)
      (json-parse-string (buffer-string) :object-type 'alist :array-type 'list)))

(defconst feature-keywords-per-language
  (feature-load-gherkin-i10n feature-i18n-file))

(defun feature-get-language-data (language)
  "Grabs the translated properties for LANGUAGE in the Gherkin translations file."
  (assoc (intern (substring-no-properties language)) feature-keywords-per-language))

(defface feature-background-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Background keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-and-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for the Background keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-but-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for the But keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-examples-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Examples keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-feature-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Feature keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-given-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for the Given keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-rule-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Rule keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-scenario-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Scenario keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-scenarioOutline-keyword-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for the Scenario Outline keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-then-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for the Then keyword in Cucumber features."
  :group 'feature-mode)

(defface feature-when-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "Face for the When keyword in feature files."
  :group 'feature-mode)

;;
;; Keymap
;;

(defvar feature-mode-map nil "Keymap used in feature mode.")

(if feature-mode-map
    nil
  (setq feature-mode-map (make-sparse-keymap))
  (define-key feature-mode-map "\C-m" 'newline)
  (define-key feature-mode-map  (kbd "C-c ,s") 'feature-verify-scenario-at-pos)
  (define-key feature-mode-map  (kbd "C-c ,v") 'feature-verify-all-scenarios-in-buffer)
  (define-key feature-mode-map  (kbd "C-c ,f") 'feature-verify-all-scenarios-in-project)
  (define-key feature-mode-map  (kbd "C-c ,g") 'feature-goto-step-definition)
  (define-key feature-mode-map  (kbd "M-.") 'feature-goto-step-definition))

;; Add relevant feature keybindings to ruby modes
(add-hook 'ruby-mode-hook
          (lambda ()
            (local-set-key (kbd "C-c ,f") 'feature-verify-all-scenarios-in-project)))


;;
;; Syntax table
;;

(defvar feature-mode-syntax-table nil
  "Syntax table in use in `ruby-mode' buffers.")

(unless feature-mode-syntax-table
  (setq feature-mode-syntax-table (make-syntax-table)))

;; Constants

(defconst feature-blank-line-re "^[ \t]*\\(?:#.*\\)?$"
  "Regexp matching a line containing only whitespace.")

(defconst feature-example-line-re "^[ \t]*|"
  "Regexp matching a line containing scenario example.")

(defconst feature-tag-line-re "^[ \t]*@"
  "Regexp matching a tag/annotation.")

(defconst feature-pystring-re "^[ \t]*\"\"\"$"
  "Regexp matching a pystring.")

(defun feature-build-keywords-re (keywords)
  "Builds the regex to match KEYWORDS."
  (eval `(rx line-start
             (zero-or-more space)
             (or ,@keywords)
             (optional ":"))))

(defun feature--translated-keywords-for (keyword language)
  "Return the translated keywords for KEYWORD in the specified LANGUAGE."
  (cdr (assoc keyword (cdr (feature-get-language-data language)))))

;; FIXME: this wants a refactor, maybe just an assoc keyword => regexp?
(defun feature-feature-re (language)
  "Return a regexp matching the feature keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'feature language)))

(defun feature-scenario-re (language)
  "Return a regexp matching the scenario keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'scenario language)))

(defun feature-scenario_outline-re (language)
  "Return a regexp matching the scenarioOutline keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'scenarioOutline language)))

(defun feature-examples-re (language)
  "Return a regexp matching the examples keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'examples language)))

(defun feature-background-re (language)
  "Return a regexp matching the background keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'background language)))

(defun feature-rule-re (language)
  "Return a regexp matching the rule keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'rule language)))

(defun feature-given-re (language)
  "Return a regexp matching the given keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'given language)))

(defun feature-when-re (language)
  "Return a regexp matching the when keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'when language)))

(defun feature-then-re (language)
  "Return a regexp matching the then keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'then language)))

(defun feature-and-re (language)
  "Return a regexp matching the and keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'and language)))

(defun feature-but-re (language)
  "Return a regexp matching the but keyword in the specified LANGUAGE."
  (feature-build-keywords-re (feature--translated-keywords-for 'but language)))

;;
;; Variables
;;

(defvar feature-mode-hook nil
  "Hook run when entering `feature-mode'.")

(defcustom feature-indent-initial-offset 0
  "Indentation of the first file."
  :type 'integer :group 'feature-mode)

(defcustom feature-indent-level 2
  "Indentation of feature statements."
  :type 'integer :group 'feature-mode)

(defcustom feature-indent-offset 2
  "*Amount of offset per level of indentation."
  :type 'integer :group 'feature-mode)

;; FIXME: this is confusing
(defun feature-given-when-then-wordlength (lang)
  "Computes the right offset for LANG."
  (let* ((when-then-and-words '(given when then and but))
         (language-keywords (cdr (assoc lang feature-keywords-per-language)))
         (rexes (append (mapcar
                         (lambda (kw) (cdr (assoc kw language-keywords)))
                         when-then-and-words))))
    (beginning-of-line)
    ;; white-space means offset -1
    (if (or (bobp) (eobp))
        nil
      (if (looking-at feature-blank-line-re)
          0
        (if (cl-some (lambda (rex) (looking-at rex)) rexes)
            (length (match-string 1))
          nil)))))


(defun feature-compute-given-when-then-offset (lang)
  "Computes the right offset for LANG bis." ;; FIXME
  (if feature-align-steps-after-first-word
      (let ((current-word-length (feature-given-when-then-wordlength lang)))
        (cond
         ;; a non-given-when-then-line doesn't adjust the
         ;; offset
         ((null current-word-length) 0)
         ;; the same happens for empty lines
         ((= 0 current-word-length) 0)
         ;; we are on a proper line, figure out
         ;; the lengths of all lines preceding us
         (t (let* ((search)
                   (search (lambda (direction lang)
                             (forward-line direction)
                             (let ((search-word-length (feature-given-when-then-wordlength lang)))
                               (cond
                                ((null search-word-length) nil)
                                (t (cons search-word-length (funcall search direction lang)))))))
                   (previous-lengths (delq 0 (save-excursion
                                               (funcall search -1 lang)))))
              (if previous-lengths
                  (- (car previous-lengths) current-word-length)
                0)))))
    0))

(defun feature-search-for-regex-match (key)
  "Walks back the buffer to get the KEY lambda to match something."
  (forward-line -1)
  (while (and (not (funcall key)) (not (bobp)))
    (forward-line -1)))

(defun feature-compute-indentation ()
  "Calculate the maximum sensible indentation for the current line."
  (save-excursion
    (beginning-of-line)
    (if (bobp) feature-indent-initial-offset
      (let* ((lang (feature-detect-language))
             (given-when-then-offset (feature-compute-given-when-then-offset lang))
             (saved-indentation (current-indentation)))
        (cond
         ((looking-at (feature-feature-re lang))
          (progn
            (feature-search-for-regex-match (lambda () (looking-at (feature-feature-re lang))))
            (current-indentation)))
         ((or (looking-at (feature-background-re lang))
              (looking-at (feature-scenario-re lang))
              (looking-at feature-tag-line-re))
          (progn
            (feature-search-for-regex-match
             (lambda () (or (looking-at (feature-feature-re lang))
                            (looking-at feature-tag-line-re)
                            (looking-at (feature-background-re lang))
                            (looking-at (feature-scenario-re lang)))))
            (cond
             ((or (looking-at (feature-feature-re lang))
                  (looking-at feature-tag-line-re))
              feature-indent-level)
             ((or (looking-at (feature-background-re lang))
                  (looking-at (feature-scenario-re lang)))
              (current-indentation))
             (t saved-indentation))))
         ((looking-at (feature-examples-re lang))
          (progn
            (feature-search-for-regex-match
             (lambda () (or (looking-at (feature-background-re lang))
                            (looking-at (feature-scenario-re lang)))))
            (if (or (looking-at (feature-background-re lang)) (looking-at (feature-scenario-re lang)))
                (+ (current-indentation) feature-indent-offset)
              saved-indentation)))
         ((or (looking-at (feature-given-re lang))
              (looking-at (feature-when-re lang))
              (looking-at (feature-then-re lang))
              (looking-at (feature-and-re lang))
              (looking-at (feature-but-re lang)))
          (progn
            (feature-search-for-regex-match
             (lambda () (or (looking-at (feature-background-re lang))
                            (looking-at (feature-scenario-re lang))
                            (looking-at (feature-given-re lang))
                            (looking-at (feature-when-re lang))
                            (looking-at (feature-then-re lang))
                            (looking-at (feature-and-re lang))
                            (looking-at (feature-but-re lang)))))
            (cond
             ((or (looking-at (feature-background-re lang)) (looking-at (feature-scenario-re lang)))
              (+ (current-indentation) feature-indent-offset))
             ((or (looking-at (feature-given-re lang))
                  (looking-at (feature-when-re lang))
                  (looking-at (feature-then-re lang))
                  (looking-at (feature-and-re lang))
                  (looking-at (feature-but-re lang)))
              (current-indentation))
             (t saved-indentation))))
         ((or (looking-at feature-example-line-re) (looking-at feature-pystring-re))
          (progn
            (feature-search-for-regex-match
             (lambda () (or (looking-at (feature-examples-re lang))
                            (looking-at (feature-given-re lang))
                            (looking-at (feature-when-re lang))
                            (looking-at (feature-then-re lang))
                            (looking-at (feature-and-re lang))
                            (looking-at (feature-but-re lang))
                            (looking-at feature-example-line-re))))
            (cond
             ((or (looking-at (feature-examples-re lang))
                  (looking-at (feature-given-re lang))
                  (looking-at (feature-when-re lang))
                  (looking-at (feature-then-re lang))
                  (looking-at (feature-and-re lang))
                  (looking-at (feature-but-re lang)))
              (+ (current-indentation) feature-indent-offset))
             ((or (looking-at feature-example-line-re)
                  (looking-at feature-pystring-re))
              (current-indentation))
             (t saved-indentation))))
         (t
          (progn
            (feature-search-for-regex-match (lambda () (not (looking-at feature-blank-line-re))))
            (+ (current-indentation)
               given-when-then-offset
               (if (or (looking-at (feature-feature-re lang))
                       (looking-at (feature-scenario-re lang))
                       (looking-at (feature-background-re lang)))
                   feature-indent-offset 0)))))))))

(defun feature-indent-line ()
  "Indent the current line.
The first time this command is used, the line will be indented to the
maximum sensible indentation.  Each immediately subsequent usage will
back-dent the line by `feature-indent-offset' spaces.  On reaching column
0, it will cycle back to the maximum sensible indentation."
  (interactive "*")
  (let ((ci (current-indentation))
        (need (feature-compute-indentation)))
    (save-excursion
      (beginning-of-line)
      (delete-horizontal-space)
      (if (and (equal last-command this-command) (/= ci 0) feature-enable-back-denting (called-interactively-p 'any))
          (indent-to (* (/ (- ci 1) feature-indent-offset) feature-indent-offset))
        (indent-to need)))
    (if (< (current-column) (current-indentation))
        (forward-to-indentation 0))))

(defadvice orgtbl-tab (before feature-indent-table-advice (&optional arg))
  "Override the indentation set by org-table."
  (feature-indent-line))
(ad-activate 'orgtbl-tab)


(defun feature-detect-language ()
  "Detect the language of the current file based on the language meta comment."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "language: \\([[:alpha:]-]+\\)"
                           (line-end-position)
                           t)
        (match-string 1)
      feature-default-language)))

(defun feature-mode-variables ()
  "Setup the variables for `feature-mode'."
  (set-syntax-table feature-mode-syntax-table)
  (when mode-require-final-newline
    (setq require-final-newline t))
  (setq comment-start "# ")
  (setq comment-start-skip "#+ *")
  (setq comment-end "")
  (setq parse-sexp-ignore-comments t)
  (set (make-local-variable 'indent-tabs-mode) 'nil)
  (set (make-local-variable 'indent-line-function) 'feature-indent-line))

(defun feature-minor-modes ()
  "Enable/disable all minor modes for feature mode."
  (turn-on-orgtbl)
  (set (make-local-variable 'electric-indent-functions)
       (list (lambda () 'no-indent))))

(defun feature-mode--fontlock-for-keyword (keyword language)
  "Form the font lock structure to highlight KEYWORD in LANGUAGE."
  (let ((re-function (intern (format "feature-%s-re" keyword)))
        (face (intern (format "feature-%s-keyword-face" keyword))))
    `(,(funcall re-function language) 0 ',face)))

(defun feature-mode--fontlock-regexps (language)
  "Form the font lock table for LANGUAGE.
Iterate every keyword in `feature-mode--keywords' and write the matching
font lock table with LANGUAGE."
  (mapcar
   (lambda (keyword) (feature-mode--fontlock-for-keyword keyword language))
   feature-mode--keywords))

(defvar feature-mode--fontlock-static
  '(("<[^>]*>"  . font-lock-variable-name-face)
    ("^ *@.*"   . font-lock-preprocessor-face)
    ("^ *#.*"     0 font-lock-comment-face t)))

(defun feature-mode-setup-fontlock ()
  "Set up the font locking for the file."
  (let ((language (feature-detect-language)))
    (setq font-lock-defaults (list
                              (append
                               feature-mode--fontlock-static
                               (feature-mode--fontlock-regexps language))))
    (font-lock-refresh-defaults)))

;;
;; Mode function
;;

;;;###autoload
(define-derived-mode
  feature-mode
  text-mode
  "Feature"
  "Major mode for editing Gherkin (i.e. Cucumber) user stories."
  (kill-all-local-variables)
  (use-local-map feature-mode-map)
  (setq mode-name "Feature")
  (setq major-mode 'feature-mode)
  (feature-mode-variables)
  (feature-minor-modes)
  (feature-mode-setup-fontlock)
  (run-mode-hooks 'feature-mode-hook))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.feature\\'" . feature-mode))

;;
;; Snippets
;;

(defvar feature-snippet-directory (concat (file-name-directory load-file-name) "snippets")
  "Path to the `feature-mode' snippets.

If the yasnippet library is loaded, snippets in this directory
are loaded on startup.  If nil, don't load snippets.")

(defvar feature-support-directory (concat (file-name-directory load-file-name) "support")
  "Path to the support folder.

   The support folder contains a ruby script that takes a step as an
   argument, and outputs a list of all matching step definitions")

(declare-function yas/load-directory "yasnippet" t)
(when (and (featurep 'yasnippet)
           feature-snippet-directory
           (file-exists-p feature-snippet-directory))
  (yas/load-directory feature-snippet-directory))


;;
;; Verifying features
;;

(defun feature-verify-scenario-at-pos ()
  "Run the scenario at point."
  (interactive)
  (feature-run-cucumber
   (list "-l" (number-to-string (line-number-at-pos)))
   :feature-file (buffer-file-name)))

(defun feature-verify-all-scenarios-in-buffer ()
  "Run all the scenarios defined in current buffer."
  (interactive)
  (feature-run-cucumber '() :feature-file (buffer-file-name)))


(defun feature-verify-all-scenarios-in-project ()
  "Run all the scenarios defined in current project."
  (interactive)
  (feature-run-cucumber '()))

(defun feature-register-verify-redo (redoer)
  "Register a bit of code that will repeat a verification process.
Argument REDOER"
  (let ((redoer-cmd (eval (list 'lambda ()
                                '(interactive)
                                (list 'let (list (list `default-directory
                                                       default-directory))
                                      redoer)))))

    (global-set-key (kbd "C-c ,r") redoer-cmd)))

(defun feature-project-file-exists (filename)
  "Determine if the project has a root file matching FILENAME."
  (file-exists-p (concat (feature-project-root) filename)))

(defun feature-can-run-bundle ()
  "Determine if bundler is installed and a Gemfile exists."
  (and (feature-project-file-exists "Gemfile")
       (executable-find "bundle")))

(defun feature-should-run-docker-compose ()
  "Determine if `docker-compose' should be used."
  (and (feature-project-file-exists "docker-compose.yml")
       feature-use-docker-compose))

(defun feature-construct-cucumber-command (command-template opts-str feature-arg)
  "Builds the command for FEATURE-ARG spec with COMMAND-TEMPLATE, passing OPTS-STR."
  (let ((base-command
         (concat (replace-regexp-in-string
                  "{options}" opts-str
                  (replace-regexp-in-string "{feature}"
                                            (if (feature-should-run-docker-compose) (replace-regexp-in-string (feature-project-root) "" feature-arg) feature-arg)
                                            command-template) t t))))
    (concat (if (feature-should-run-docker-compose) (concat feature-docker-compose-command " run " feature-docker-compose-container " ") "")
            (concat (if (feature-can-run-bundle) "bundle exec " "")
                    base-command))))

(cl-defun feature-run-cucumber (cuke-opts &key feature-file)
  "Run cucumber with the specified CUKE-OPTS options for FEATURE-FILE."
  (feature-register-verify-redo (list 'feature-run-cucumber
                                      (list 'quote cuke-opts)
                                      :feature-file feature-file))
  ;; redoer is registered

  (let ((opts-str    (mapconcat 'identity cuke-opts " "))
        (feature-arg (or feature-file
                         feature-default-directory))
        (command-template (if (feature-project-file-exists "Rakefile")
                              feature-rake-command
                            feature-cucumber-command)))
    (ansi-color-for-comint-mode-on)
    (let ((default-directory (feature-project-root)))
      (when feature-use-rvm
        (rvm-activate-corresponding-ruby))
      (when feature-use-chruby
        (chruby-use-corresponding))
      (compile (feature-construct-cucumber-command command-template opts-str feature-arg) t))))

(defun feature-root-directory-p (a-directory)
  "Test if A-DIRECTORY is the root of the directory tree (i.e. is it '/' on unix)."
  (equal a-directory (file-name-directory (directory-file-name a-directory))))

(defun feature-project-root (&optional directory)
  "Find the root directory of the project starting from DIRECTORY.
The search is done by walking the directory tree until the
file/directory set by `feature-root-marker-file-name' is found."
  (let ((directory (file-name-as-directory (or directory default-directory))))
    (if (feature-root-directory-p directory)
        (error (concat "Could not find " feature-root-marker-file-name)))
    (if (file-exists-p (concat directory feature-root-marker-file-name))
        directory
      (feature-project-root (file-name-directory (directory-file-name directory))))))

(defun feature-find-step-definition (action)
  "Find the step-definition under point and call ACTION if found."
  (let* ((root (feature-project-root))
         (input (thing-at-point 'line))
         (_ (set-text-properties 0 (length input) nil input))
         (result (shell-command-to-string (format "cd %S && %s %S/find_step.rb %s %s %S %s %s"
                                                  (feature-project-root)
                                                  feature-ruby-command
                                                  feature-support-directory
                                                  (feature-detect-language)
                                                  (buffer-file-name)
                                                  (line-number-at-pos)
                                                  (shell-quote-argument feature-step-search-path)
                                                  (shell-quote-argument feature-step-search-gems-path))))
         (matches (read result))
         (matches-length (safe-length matches)))

    (if (listp matches)
        (if (> matches-length 0)
            (let* ((file-and-line (if (= matches-length 1)
                                      (cdr (car matches))
                                    (cdr (assoc (ido-completing-read "Which example needed? " (mapcar (lambda (pair) (car pair))  matches)) matches))))
                   (matched? (string-match "^\\(.+\\):\\([0-9]+\\)$" file-and-line)))
              (if matched?
                  (let ((file (format "%s/%s" root (match-string 1 file-and-line)))
                        (line-no (string-to-number (match-string 2 file-and-line))))
                    (funcall action file line-no))
                (message "An error occured: \n%s" result)))
          (message "No matching steps found for:\n%s" input))
      (message "An error occured: \n%s" result))))

(defun feature-goto-step-definition ()
  "Goto the step-definition under (point).  Requires ruby."
  (interactive)
  (feature-find-step-definition
   (lambda (file line-no)
     (progn
       (xref-push-marker-stack)
       (find-file file)
       (goto-char (point-min))
       (forward-line (1- line-no))))))

(provide 'cucumber-mode)
(provide 'feature-mode)
;;; feature-mode.el ends here
