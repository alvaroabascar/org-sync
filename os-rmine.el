;;; os-rmine.el --- Redmine backend for org-sync.

;; Copyright (C) 2012  Aurelien Aptel
;;
;; Author: Aurelien Aptel <aurelien dot aptel at gmail dot com>
;; Keywords: org, redmine, synchronization
;; Homepage: http://orgmode.org/worg/org-contrib/gsoc2012/student-projects/org-sync
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; This file is not part of GNU Emacs.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package implements a backend for org-sync to synchnonize
;; issues from a redmine repo with an org-mode buffer.  Read Org-sync
;; documentation for more information about it.

;;; Code:

(eval-when-compile (require 'cl))
(require 'org-sync)
(require 'url)
(require 'json)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defvar os-rmine-backend
  '((base-url      . os-rmine-base-url)
    (fetch-buglist . os-rmine-fetch-buglist)
    (send-buglist  . os-rmine-send-buglist))
  "Redmine backend.")

(defvar os-rmine-auth nil
  "Redmine login (\"user\" . \"pwd\")")

(defvar os-rmine-date-regex
  (rx
   (seq
    (group (repeat 4 digit)) "/"
    (group (repeat 2 digit)) "/"
    (group (repeat 2 digit))
    " "
    (group
     (repeat 2 digit) ":"
     (repeat 2 digit) ":"
     (repeat 2 digit))
    " "
    (group (or "+" "-")
           (repeat 2 digit)
           (repeat 2 digit))))
  "Regex to parse date returned by redmine.")

(defun os-rmine-parse-date (date)
  "Return time object of DATE."
  (when (string-match os-rmine-date-regex date)
    (os-parse-date (concat (match-string 1 date) "-"
                           (match-string 2 date) "-"
                           (match-string 3 date) "T"
                           (match-string 4 date)
                           (match-string 5 date)))))

(defun os-rmine-request (method url &optional data)
  "Send HTTP request at URL using METHOD with DATA.
AUTH is a cons (\"user\" . \"pwd\").  Return the server
decoded response in JSON."
  (message "%s %s %s" method url (prin1-to-string data))
  (let* ((url-request-method method)
         (url-request-data data)
         (url-request-extra-headers
          (when data
            '(("Content-Type" . "application/json"))))
         (auth os-rmine-auth)
         (buf))

    (if (consp auth)
        ;; dynamically bind auth related vars
        (let* ((str (concat (car auth) ":" (cdr auth)))
               (encoded (base64-encode-string str))
               (login `(("www.hostedredmine.com" ("Redmine API" . ,encoded))))
               (url-basic-auth-storage 'login))
          (setq buf (url-retrieve-synchronously url)))
      ;; nothing more to bind
      (setq buf (url-retrieve-synchronously url)))
    (with-current-buffer buf
      (goto-char url-http-end-of-headers)
      (prog1
          (cons url-http-response-status (ignore-errors (json-read)))
        (kill-buffer)))))

;; override
(defun os-rmine-base-url (url)
  "Return base URL."
  (when (string-match "^\\(?:https?://\\)?\\(?:www\\.\\)?hostedredmine.com/projects/\\([^/]+\\)" url)
    (concat "http://www.hostedredmine.com/projects/" (match-string 1 url))))

(defun os-rmine-repo-name (url)
  "Return repo name at URL."
  (when (string-match "projects/\\([^/]+\\)" url)
    (match-string 1 url)))

(defun os-rmine-json-to-bug (json)
  "Return JSON as a bug."
  (flet ((va (key alist) (cdr (assoc key alist)))
         (v (key) (va key json)))
    (let* ((id (v 'id))
           (author (va 'name (v 'author)))
           (txtstatus (va 'name (v 'status)))
           (status (if (or (string= txtstatus "Open")
                           (string= txtstatus "New"))
                       'open
                     'closed))
           (priority (va 'name (v 'priority)))
           (title (v 'subject))
           (desc (v 'description))
           (ctime (os-rmine-parse-date (v 'created_on)))
           (mtime (os-rmine-parse-date (v 'updated_on))))

      `(:id ,id
            :priority ,priority
            :status ,status
            :title ,title
            :desc ,desc
            :date-creation ,ctime
            :date-modification ,mtime))))


(defun os-rmine-fetch-buglist (last-update)
  "Return the buglist at os-base-url."
  (let* ((url (concat os-base-url "/issues.json"))
         (res (os-rmine-request "GET" url))
         (code (car res))
         (json (cdr res))
         (title (concat "Bugs of " (os-rmine-repo-name url))))

    `(:title ,title
             :url ,os-base-url
             :bugs ,(mapcar 'os-rmine-json-to-bug (cdr (assoc 'issues json))))))