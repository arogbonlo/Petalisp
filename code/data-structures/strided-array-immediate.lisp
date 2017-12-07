;;; © 2016-2017 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

(define-class strided-array-immediate (strided-array immediate)
  ((storage :type (or array null))))

(defmethod shared-initialize :after
    ((instance strided-array-immediate) slot-names &key &allow-other-keys)
  (let ((from-storage (from-storage-transformation (index-space instance))))
    (setf (slot-value instance 'from-storage) from-storage)
    (setf (slot-value instance 'to-storage) (inverse from-storage))))

(defmethod make-immediate ((array array))
  (let ((element-type (atomic-array-element-type-specifier array))
        (index-space (index-space array))
        (identity (identity-transformation (dimension array))))
    (make-instance 'strided-array-immediate
      :element-type element-type
      :index-space index-space
      :storage array
      :to-storage identity
      :from-storage identity)))

(defmethod corresponding-immediate ((strided-array strided-array))
  (make-instance 'strided-array-immediate
    :element-type (element-type strided-array)
    :index-space (index-space strided-array)))

(defun from-storage-transformation (index-space)
  "Return a non-permuting, affine transformation from a zero based array
   with step size one to the given INDEX-SPACE."
  (let ((ranges (ranges index-space))
        (dimension (dimension index-space)))
    (affine-transformation
     (make-array dimension :initial-element nil)
     (scaled-permutation-matrix
      dimension dimension
      (apply #'vector (iota dimension))
      (map 'vector #'range-step ranges))
     (map 'vector #'range-start ranges))))

(defmethod make-immediate! ((strided-array strided-array))
  (change-class strided-array 'strided-array-immediate))

(defmethod application or ((f function) (a1 strided-array-immediate) &rest a2...aN)
  "Constant-fold operations on scalar values."
  (when (and (= 1 (size a1)) (every #'strided-array-immediate? a2...aN))
    (let ((value (apply f (row-major-aref (storage a1) 0)
                        (mapcar (λ ak (row-major-aref (storage ak) 0)) a2...aN))))
      (broadcast (make-immediate value) (index-space a1)))))

(defmethod application or ((f function) (a1 strided-array-reference) &rest a2...aN)
  "Constant-fold operations on references to scalar values."
  (flet ((scalar-reference? (a)
           (when (strided-array-reference? a)
             (let ((input (input a)))
               (and (strided-array-immediate? input)
                    (= 1 (size input)))))))
    (when (and (scalar-reference? a1) (every #'scalar-reference? a2...aN))
      (let ((value (apply f (row-major-aref (storage (input a1)) 0)
                          (mapcar (λ ak (row-major-aref (storage (input ak)) 0)) a2...aN))))
        (reference (make-immediate value) (index-space a1) (transformation a1))))))

(defmethod print-object
    ((strided-array-immediate strided-array-immediate)
     stream)
  (print-unreadable-object (strided-array-immediate stream :type t :identity t)
    (princ (storage strided-array-immediate) stream)))
