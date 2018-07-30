;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp)

(defclass default-scheduler-mixin ()
  ((%scheduler-queue :reader scheduler-queue
                     :initform (lparallel.queue:make-queue))
   (%scheduler-thread :initarg :scheduler-thread
                      :accessor scheduler-thread)
   (%worker-queue :reader worker-queue
                  :initform (lparallel.queue:make-queue))
   (%worker-thread :initarg :worker-thread
                   :accessor worker-thread)))

(defmethod initialize-instance :after
    ((vm default-scheduler-mixin) &key &allow-other-keys)
  (flet ((schedule ()
           (loop (funcall (lparallel.queue:pop-queue (scheduler-queue vm))))))
    (setf (scheduler-thread vm)
          (bt:make-thread #'schedule :name "Petalisp Scheduler Thread")))
  (flet ((work ()
           (loop (funcall (lparallel.queue:pop-queue (worker-queue vm))))))
    (setf (worker-thread vm)
          (bt:make-thread #'work :name "Petalisp Worker Thread"))))

;;; Instruct BACKEND to suitably set the STORAGE slot of IMMEDIATE.
(defgeneric vm/bind-memory (backend immediate))

;;; Instruct BACKEND to prepare the given BLUEPRINT for execution.
(defgeneric vm/compile (backend blueprint))

;;; Instruct BACKEND to compute the sequence of data structures
;;; GRAPH-ROOTS. Return the computed values of all GRAPH-ROOTS
(defgeneric vm/compute (backend graph-roots))

;;; Instruct BACKEND to execute the given KERNEL, assuming that all its
;;; sources and targets have already been allocated and computed.
(defgeneric vm/execute (backend kernel))

;;; Instruct BACKEND to reclaim the STORAGE of IMMEDIATE and set the
;;; STORAGE slot of IMMEDIATE to NIL.
(defgeneric vm/free-memory (backend immediate))

(defmethod vm/schedule ((vm default-scheduler-mixin) targets recipes)
  (let ((promise (lparallel.promise:promise)))
    (prog1 promise
      (flet ((work (targets kernelized-immediates)
               (lparallel.queue:push-queue
                (lambda ()
                  (loop for immediate across kernelized-immediates
                        for index from 0
                        unless (storage (aref targets index))
                          do (setf (storage (aref targets index))
                                   (storage (evaluate-naively vm immediate))))
                  (lparallel.promise:fulfill promise))
                (worker-queue vm))))
        (lparallel.queue:push-queue
         (lambda ()
           (work targets (kernelize recipes)))
         (scheduler-queue vm))))))

(defun evaluate-naively (vm immediate)
  ;; only evaluate once
  (unless (storage immediate)
    ;; evaluate all dependencies
    (let (dependencies)
      (loop for kernel across (kernels immediate) do
        (loop for index from 1 below (length (kernel-references kernel))
              for source = (aref (kernel-references kernel) index) do
                (pushnew source dependencies)))
      (map nil (lambda (dependency) (evaluate-naively vm dependency))
           dependencies))
    ;; allocate memory
    (vm/bind-memory vm immediate)
    ;; compute all kernels
    (loop for kernel across (kernels immediate) do
      (vm/execute vm kernel)
      (loop for index from 1 below (length (kernel-references kernel))
            for source = (aref (kernel-references kernel) index) do
              (when (zerop (decf (refcount source)))
                (vm/free-memory vm source)))))
  immediate)
