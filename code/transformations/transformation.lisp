;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp)

;;; Petalisp transformations are a combination of the following five
;;; elementary operations:
;;;
;;; (1) translating the indices by a constant
;;; (2) multiplying the indices by a constant
;;; (3) permuting the dimensions
;;; (4) introducing dimensions with a one element range
;;; (5) removing dimensions
;;;
;;; In linear algebra lingo, we have
;;;
;;; (1) adding a vector
;;; (2) multiplying with a diagonal matrix
;;; (3) multiplying with a permutation matrix
;;; (4) multiplying with an identity matrix, but with some zero rows inserted and adding a vector
;;; (5) multiplying with an identity matrix, but with some rows removed
;;;
;;; The transformation protocol is inspired by that of McCLIM. The
;;; difference is that McCLIM transformations are functions from R^2 to
;;; R^2, while Petalisp transformations are functions from N^n to N^m.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Generic Functions

(defgeneric canonicalize-transformation (object))

(defgeneric transformationp (object))

(defgeneric invertible-transformation-p (object))

(defgeneric transformation-equal (transformation-1 transformation-2))

(defgeneric compose-transformations (transformation-1 transformation-2))

(defgeneric invert-transformation (transformation))

(defgeneric input-dimension (transformation))

(defgeneric output-dimension (transformation))

(defgeneric input-constraints (transformation))

;;; For each output of TRANSFORMATION, invoke FUNCTION with the output
;;; index, input index and the scaling and offset necessary to project an
;;; input value at that input index to an output value at that output
;;; index.
(defgeneric map-transformation-outputs (transformation function))

;;; Given a transformation mapping from (i1 ... iN) to (j1 ... jM),
;;; return a transformation mapping from (i1 ... iN iN+1) to
;;; (j1 ... jM iN+1).
(defgeneric enlarge-transformation (transformation scale offset))

(defgeneric transform (object transformation))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Classes

(defclass transformation ()
  ())

;; Forward declaration of the primary transformation constructors, because
;; they will be referenced before being defined.
(declaim (ftype (function (&key (:input-dimension array-length)
                                (:output-dimension array-length)
                                (:input-constraints sequence)
                                (:translation sequence)
                                (:permutation sequence)
                                (:scaling sequence)))
                make-transformation)
         (ftype (function (array-length))
                make-identity-transformation))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods

(defmethod canonicalize-transformation ((transformation transformation))
  transformation)

(defmethod canonicalize-transformation ((object t))
  (error 'petalisp-user-error
         "~@<~A is not a valid transformation.~:@>"))

(defmethod transformationp (object)
  (declare (ignore object))
  nil)

(defmethod transformationp ((transformation transformation))
  (declare (ignore transformation))
  t)

(defmethod invertible-transformation-p (object)
  (declare (ignore object))
  nil)

(defmethod compose-transformations :before
    ((transformation-1 transformation) (transformation-2 transformation))
  (assert (= (output-dimension transformation-2)
             (input-dimension transformation-1))))

(defmethod input-constraints (transformation)
  (declare (ignore transformation))
  nil)

(defmethod print-object ((transformation transformation) stream)
  (let* ((variables
           (loop for index below (input-dimension transformation)
                 collect (format-symbol :keyword "I~D" index)))
         (inputs
           (if (null (input-constraints transformation))
               variables
               (loop for input-constraint across (input-constraints transformation)
                     for variable in variables
                     collect (or input-constraint variable)))))
    (princ `(τ ,inputs ,(transform inputs transformation))
           stream)))

(defmethod transform ((sequence sequence) (transformation transformation))
  (assert (= (length sequence) (input-dimension transformation))))
