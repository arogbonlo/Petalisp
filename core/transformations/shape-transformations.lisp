;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp-core)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods

(defmethod transform :before ((shape shape) (transformation transformation))
  (demand (= (rank shape) (input-rank transformation))
    "~@<Cannot apply the transformation ~A with input rank ~R ~
        to the index shape ~A with rank ~R.~:@>"
    transformation (input-rank transformation)
    shape (rank shape))
  (when-let ((input-constraints (input-constraints transformation)))
    (loop for range in (ranges shape)
          for constraint across input-constraints
          for index from 0 do
            (unless (not constraint)
              (demand (and (= constraint (range-start range))
                           (= constraint (range-end range)))
                "~@<The ~:R rank of the shape ~W violates ~
                    the input constraint ~W of the transformation ~W.~:@>"
                index shape constraint transformation)))))

(defmethod transform ((shape shape) (operator identity-transformation))
  shape)

(defmethod transform ((shape shape) (transformation hairy-transformation))
  (let ((output-ranges (make-list (output-rank transformation)))
        (input-ranges (ranges shape)))
    (flet ((store-output-range (output-index input-index scaling offset)
             (setf (elt output-ranges output-index)
                   (if (not input-index)
                       (make-range offset 1 offset)
                       (let ((input-range (elt input-ranges input-index)))
                         (make-range
                          (+ offset (* scaling (range-start input-range)))
                          (* scaling (range-step input-range))
                          (+ offset (* scaling (range-end input-range)))))))))
      (map-transformation-outputs transformation #'store-output-range))
    (apply #'make-shape output-ranges)))

(defun collapsing-transformation (shape)
  (invert-transformation
   (from-storage-transformation shape)))

;;; Return a non-permuting, affine transformation from a zero based array
;;; with step size one to the given SHAPE.
(defun from-storage-transformation (shape)
  (let ((ranges (ranges shape)))
    (make-transformation
     :scaling (map 'vector #'range-step ranges)
     :translation (map 'vector #'range-start ranges))))
