(defpackage :spamfilter (:use :common-lisp))

(ql:quickload :cl-ppcre)
(ql:quickload :com.gigamonkeys.pathnames)

(defclass words-count () 
  ((spam-cnt 
  :initarg :spam-cnt
  :accessor spam-cnt
  :initform 0)
   (ham-cnt 
  :initarg :ham-cnt
  :accessor ham-cnt
  :initform 0)
))

(defvar *words-db* (make-hash-table :test #'equal))
(defvar *total-spam-words* 0)
(defvar *total-ham-words* 0)
(defvar *total-spams* 0)
(defvar *total-hams* 0)
(defvar *total-words* 0)
(defvar *alpha* 1)

(defparameter *spam-test-dir* "dataset/test/spam")
(defparameter *ham-test-dir* "dataset/test/ham")

(defun clear-training-data ()
  (setf
   *words-db* (make-hash-table :test #'equal)
   *total-spam-words* 0
   *total-ham-words* 0
   *total-spams* 0
   *total-hams* 0
   *total-words* 0))

(defun split (text)
  (delete-duplicates
    (cl-ppcre:all-matches-as-strings "[a-zA-Z]{2,}" text)
    :test #'string=))

(defun save-word(word)
  (or (gethash word *words-db*) 
      (setf (gethash word *words-db*) 
            (make-instance 'words-count))))

(defun extract-words (text) 
  (mapcar #'save-word (split text)))

(defun print-words-db () 
  (loop for value being the hash-values of *words-db*
    using (hash-key key) 
    do (
      with-slots (ham-cnt spam-cnt) value
      (format t "~&~A: ham - ~d, spam - ~d" key ham-cnt spam-cnt))))

(defun increment-word-count (word type)
 (ecase type 
  (ham (incf (ham-cnt word)))
  (spam (incf (spam-cnt word)))))

(defun increment-total-words-count (type)
 (ecase type
  (ham (incf *total-ham-words*))
  (spam (incf *total-spam-words*)))
 (incf *total-words*))

(defun increment-total-count (type) 
 (ecase type 
  (ham (incf *total-hams*))
  (spam (incf *total-spams*))))

(defun train (text type)
  (dolist (word (extract-words text))
    (progn 
		(increment-word-count word type)
		(increment-total-words-count type)))
  (increment-total-count type))

(defun get-word-prob (word type)
 (with-slots (ham-cnt spam-cnt) (gethash word *words-db* (make-instance 'words-count))
  (ecase type
   (ham (coerce (/ (+ ham-cnt *alpha*) (+ *total-ham-words* (* *alpha* *total-words*))) 'long-float))
   (spam (coerce (/ (+ spam-cnt *alpha*) (+ *total-spam-words* (* *alpha* *total-words*))) 'long-float)))))

(defun get-text-probab (text type)
 (let ((res 1.0))
  (dolist (word (split text))
   (setq res (coerce (* res (get-word-prob word type)) 'long-float)))
  res))

(defun classify (text)
 (if (= (+ *total-hams* *total-spams*) 0) 
  (return-from classify 'unsure))
 (setq spam-prob (/ *total-spams* (+ *total-spams* *total-hams*)))
 (setq ham-prob (/ *total-hams* (+ *total-spams* *total-hams*)))
 (setq is-spam-prob (get-text-probab text 'spam))                    
 (setq is-ham-prob (get-text-probab text 'ham))	                     
 (if (> (* spam-prob is-spam-prob) (* ham-prob is-ham-prob))
  (return-from classify 'spam)
  (return-from classify 'ham)))

(defun read-file (fname) 
 (with-open-file (stream fname)
  (let ((data (make-string (file-length stream))))
   (read-sequence data stream)
   data)))

(defun train-from-dir (dir type)
 (dolist (fname (com.gigamonkeys.pathnames:list-directory dir))
   (ignore-errors (train (read-file fname) type))))

(defun classify-from-dir (dir type)
 (let ((res 'error)
	   (total 0)
	   (err 0))
   (dolist (fname (com.gigamonkeys.pathnames:list-directory dir))
	 (incf total)
     (ignore-errors (setq res (classify (read-file fname))))
     (if (not (eq res type))
	  (incf err)))
   (return-from classify-from-dir (list err total))))

(defun test-classification ()
 (setq ham-res (classify-from-dir *ham-test-dir* 'ham))
 (setq spam-res (classify-from-dir *spam-test-dir* 'spam))
 (format t "Wrong hams: ~D/~D~%Wrong spams: ~D/~D" (car ham-res) (cadr ham-res) (car spam-res) (cadr spam-res)))
