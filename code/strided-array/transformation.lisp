;;; © 2016 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

(define-class strided-array-affine-permutation (strided-array affine-permutation) ())

(defmethod transformation ((object strided-array)
                           &key scale translate permute)
  (make-instance
   'strided-array-transformation
   :object object))
