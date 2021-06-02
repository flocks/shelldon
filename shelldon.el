;;; shelldon.el --- a friendly little shell in the minibuffer  -*- lexical-binding: t; -*-

;; Copyright (C) 2021 overdr0ne

;; Author: overdr0ne <scmorris.dev@gmail.com>
;; Keywords: tools, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; https://github.com/Overdr0ne/shelldon
;; It is basically just a simple wrapper around async-shell-command that
;; primarily allows you to store and navigate separate command outputs among
;; other things.

;;; Code:

(require 'cl)

(defun shelldon-cd ()
  "Change directories without leaving shelldon context.

Get the workdir, then throw it back for the shelldon command to set it in that
context."
  (interactive)
  (let (shelldon-wd)
    (setq shelldon-wd (call-interactively #'cd))
    (throw 'shelldon-cwd shelldon-wd)))

(define-key minibuffer-local-shell-command-map (kbd "C-x C-f") #'shelldon-cd)

(defvar shelldon-hist '())
(defvar shelldon-prompt-str ">> ")
(defun shelldon-async-command (command)
  "Execute string COMMAND in inferior shell; display output, if any.
With prefix argument, insert the COMMAND's output at point.

In Elisp, you will often be better served by calling `call-process' or
`start-process' directly, since they offer more control and do not
impose the use of a shell (with its need to quote arguments)."
  (interactive
   (list
    (read-shell-command
     (if shell-command-prompt-show-cwd
         (format-message "%s%s"
                         (abbreviate-file-name
                          default-directory)
                         shelldon-prompt-str)
       shelldon-prompt-str)
     nil nil
     (let ((filename
            (cond
             (buffer-file-name)
             ((eq major-mode 'dired-mode)
              (dired-get-filename nil t)))))
       (and filename (file-relative-name filename))))))
  ;; (when current-prefix-arg (setq output-buffer current-prefix-arg))
  ;; Look for a handler in case default-directory is a remote file name.
  (let ((output-buffer (concat "*shelldon:" (number-to-string (length shelldon-hist)) ":" command "*"))
        (error-buffer shell-command-default-error-buffer)
        (handler
	 (find-file-name-handler (directory-file-name default-directory)
				 'shell-command)))
    (add-to-list 'shelldon-hist `(,(concat (number-to-string (length shelldon-hist)) ":" command) . ,output-buffer))
    (if handler
	(funcall handler 'shell-command command output-buffer error-buffer)
      ;; Output goes in a separate buffer.
      ;; Preserve the match data in case called from a program.
      ;; FIXME: It'd be ridiculous for an Elisp function to call
      ;; shell-command and assume that it won't mess the match-data!
      (save-match-data
        (let* ((buffer (get-buffer-create output-buffer))
               (proc (get-buffer-process buffer))
               (directory default-directory))
	  (with-current-buffer buffer
            (shell-command-save-pos-or-erase)
	    (setq default-directory directory)
	    (let* ((process-environment
                    (nconc
                     (list
                      (format "TERM=%s" "eterm-color")
                      (format "TERMINFO=%s" data-directory)
                      (format "INSIDE_EMACS=%s" emacs-version))
                     process-environment)))
	      (setq proc
		    (start-process-shell-command "Shell" buffer command)))
	    (setq mode-line-process '(":%s"))
	    (require 'shell) (shell-mode)
            (set-process-sentinel proc #'shell-command-sentinel)
	    ;; Use the comint filter for proper handling of
	    ;; carriage motion (see comint-inhibit-carriage-motion).
            (set-process-filter proc #'comint-output-filter)
            (if async-shell-command-display-buffer
                ;; Display buffer immediately.
                (display-buffer buffer '(nil (allow-no-window . t)))
              ;; Defer displaying buffer until first process output.
              ;; Use disposable named advice so that the buffer is
              ;; displayed at most once per process lifetime.
              (let ((nonce (make-symbol "nonce")))
                (add-function :before (process-filter proc)
                              (lambda (proc _string)
                                (let ((buf (process-buffer proc)))
                                  (when (buffer-live-p buf)
                                    (remove-function (process-filter proc)
                                                     nonce)
                                    (display-buffer buf))))
                              `((name . ,nonce)))))
            ;; FIXME: When the output buffer is hidden before the shell process is started,
            ;; ANSI colors are not displayed. I have no idea why.
            (view-mode)
            (rename-buffer (concat " " output-buffer)))))))
  nil)
(defun shelldon ()
  "Execute given asynchronously in the minibuffer with output history.

If the user tries to change the workdir while the command is executing, catch
the change and re-execute in the new context."
  (interactive)
  (let ((rtn t))
    (while rtn
      (setq rtn (catch 'shelldon-cwd (call-interactively #'shelldon-async-command)))
      (when rtn
        (setq default-directory rtn)
        (setq list-buffers-directory rtn)))))

(defun shelldon-loop ()
  "Loops the shelldon command to more closely emulate a terminal."
  (interactive)
  (loop (call-interactively #'shelldon)))

(defun shelldon-output-history ()
  "Displays the output of the selected command from the shelldon history."
  (interactive)
  (switch-to-buffer (cdr (assoc (completing-read shelldon-prompt-str shelldon-hist) shelldon-hist))))
(defalias 'shelldon-hist 'shelldon-output-history
  "shelldon-hist is deprecated, use shelldon-output-history")

(add-to-list 'display-buffer-alist
	     `("*\\(shelldon.*\\)"
	       (display-buffer-reuse-window display-buffer-in-previous-window display-buffer-in-side-window)
	       (side . right)
	       (slot . 0)
	       (window-width . 80)
	       (reusable-frames . visible)))

(provide 'shelldon)

;;; shelldon.el ends here
