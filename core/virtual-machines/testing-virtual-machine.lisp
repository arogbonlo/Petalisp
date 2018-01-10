;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING

(uiop:define-package :petalisp/core/virtual-machines/testing-virtual-machine
  (:use :closer-common-lisp :alexandria)
  (:use
   :petalisp/utilities/all
   :petalisp/core/petalisp
   :petalisp/core/transformations/all
   :petalisp/core/data-structures/all))

(in-package :petalisp/core/virtual-machines/testing-virtual-machine)

;;; For testing purposes, it is useful to compute the same recipes using
;;; different virtual machines and compare the result.
;;;
;;; The testing virtual machine is constructed from a sequence of other
;;; virtual machines. Each VM/SCHEDULE instruction is then dispatched among
;;; these and the results are compared. If there is a mismatch, an error is
;;; signaled.

(define-class testing-virtual-machine (virtual-machine)
  ((virtual-machines :type sequence
                     :initform (required-argument "virtual-machines"))))

(defmethod vm/schedule ((vm testing-virtual-machine) targets recipes)
  (let ((results
          (map 'vector
               (lambda (vm)
                 (let ((targets (map 'vector #'shallow-copy targets)))
                   (wait (vm/schedule vm targets recipes))
                   targets))
               (virtual-machines vm))))
    (unless (identical results :test #'equal?)
      (error "Different virtual machines compute different results for the same recipes:~%~A"
             results))
    (loop for target across targets
          for vm-target across (elt results 0)
          do (setf (storage target) (storage vm-target)))
    (complete (make-request))))
