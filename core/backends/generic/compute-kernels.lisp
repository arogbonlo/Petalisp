;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Conversion of Subtree Fragments to Kernels
;;;
;;; The goal is to convert a given subtree of a data flow graph to a list
;;; of kernels.  The subtree is delimited by nodes that have a
;;; corresponding entry in the buffer table.  By choosing the iteration
;;; space of our kernels appropriately, we can eliminate all fusion nodes
;;; in the subtree.
;;;
;;; The algorithm consists of two phases.  In the first phase, we compute a
;;; partitioning of the shape of the root into multiple iteration spaces.
;;; These spaces are chosen such that their union is the shape of the root,
;;; but such that each iteration space selects only a single input of each
;;; encountered fusion node.  In the second phase, each iteration space is
;;; used to create one kernel and its body.  The body of a kernel is an
;;; s-expression describing the interplay of applications, reductions and
;;; references.

(defmethod compute-kernels ((root strided-array) (backend backend))
  (loop for iteration-space in (compute-iteration-spaces root)
        collect
        (let ((body (compute-kernel-body root iteration-space)))
          (make-kernel iteration-space body backend))))

;;; An immediate node has no kernels
(defmethod compute-kernels ((root immediate) (backend backend))
  '())

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Kernel Iteration Spaces

(defvar *kernel-iteration-spaces*)

(defun compute-iteration-spaces (root)
  (let ((*kernel-iteration-spaces* '()))
    (compute-iteration-spaces-aux
     root
     root
     (shape root)
     (make-identity-transformation (dimension root)))
    ;; The list of iteration spaces generated by COMPUTE-ITERATION-SPACES
    ;; may be empty if there are zero fusion nodes in the subtree.  In this
    ;; case, we return the shape of the root instead.
    (or *kernel-iteration-spaces*
        (list (shape root)))))

;;; Return a boolean indicating whether any of the inputs of NODE, or any
;;; of the inputs thereof, is a fusion node.  Furthermore, whenever NODE is
;;; a fusion node, push a new iteration space for each input that contains
;;; no further fusion nodes.
(defgeneric compute-iteration-spaces-aux
    (root node iteration-space transformation))

(defmethod compute-iteration-spaces-aux :around
    ((root strided-array)
     (node strided-array)
     (iteration-space shape)
     (transformation transformation))
  (if (eq root node)
      (call-next-method)
      (if (nth-value 1 (gethash node *buffer-table*))
          nil
          (call-next-method))))

(defmethod compute-iteration-spaces-aux
    ((root strided-array)
     (fusion fusion)
     (iteration-space shape)
     (transformation transformation))
  ;; Check whether any inputs are free of fusion nodes.  If so, push an
  ;; iteration space.
  (loop for input in (inputs fusion) do
    (let ((subspace (set-intersection iteration-space (shape input))))
      ;; If the input is unreachable, we do nothing.
      (unless (set-emptyp subspace)
        ;; If the input contains fusion nodes, we also do nothing.
        (unless (compute-iteration-spaces-aux root input subspace transformation)
          ;; We have an outer fusion.  This means we have to add a new
          ;; iteration space, which we obtain by projecting the current
          ;; iteration space to the coordinate system of the root.
          (push (transform subspace (invert-transformation transformation))
                *kernel-iteration-spaces*)))))
  t)

(defmethod compute-iteration-spaces-aux
    ((root strided-array)
     (reference reference)
     (iteration-space shape)
     (transformation transformation))
  (compute-iteration-spaces-aux
   root
   (input reference)
   (transform
    (set-intersection iteration-space (shape reference))
    (transformation reference))
   (compose-transformations (transformation reference) transformation)))

(defmethod compute-iteration-spaces-aux
    ((root strided-array)
     (reduction reduction)
     (iteration-space shape)
     (transformation transformation))
  (let* ((range (reduction-range reduction))
         (size (set-size range))
         (iteration-space
           (enlarge-shape
            iteration-space
            (make-range 0 1 (1- size))))
         (transformation
           (enlarge-transformation
            transformation
            (range-step range)
            (range-start range))))
    (loop for input in (inputs reduction)
            thereis
            (compute-iteration-spaces-aux root input iteration-space transformation))))

(defmethod compute-iteration-spaces-aux
    ((root strided-array)
     (application application)
     (iteration-space shape)
     (transformation transformation))
  (loop for input in (inputs application)
          thereis
          (compute-iteration-spaces-aux root input iteration-space transformation)))

(defmethod compute-iteration-spaces-aux
    ((root strided-array)
     (immediate immediate)
     (iteration-space shape)
     (transformation transformation))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Computing the Kernel Body

(defun compute-kernel-body (root iteration-space)
  `(pstore
    ,(gethash root *buffer-table*)
    ,(compute-kernel-body-aux
      root
      root
      iteration-space
      (make-identity-transformation (dimension root)))))

(defgeneric compute-kernel-body-aux
    (root node iteration-space transformation))

;; Check whether we are dealing with a leaf, i.e., a node that has a
;; corresponding entry in the buffer table and is not the root node.  If
;; so, return a reference to that buffer.
(defmethod compute-kernel-body-aux :around
    ((root strided-array)
     (node strided-array)
     (iteration-space shape)
     (transformation transformation))
  (unless (set-emptyp iteration-space)
    (if (eq root node)
        (call-next-method)
        (multiple-value-bind (buffer buffer-p)
            (gethash node *buffer-table*)
          (if (not buffer-p)
              (call-next-method)
              `(pref ,buffer ,transformation))))))

(defmethod compute-kernel-body-aux
    ((root strided-array)
     (application application)
     (iteration-space shape)
     (transformation transformation))
  `(pcall
    ,(value-n application)
    ,(operator application)
    ,.(loop for input in (inputs application)
            collect (compute-kernel-body-aux
                     root
                     input
                     iteration-space
                     transformation))))

(defmethod compute-kernel-body-aux
    ((root strided-array)
     (reduction reduction)
     (iteration-space shape)
     (transformation transformation))
  (let* ((range (reduction-range reduction))
         (size (set-size range))
         (scale (range-step range))
         (offset (range-start range))
         (new-range (make-range 0 1 (1- size))))
    `(preduce
      ,size
      ,(value-n reduction)
      ,(operator reduction)
      ,.(let ((iteration-space (enlarge-shape iteration-space new-range))
              (transformation (enlarge-transformation transformation scale offset)))
          (loop for input in (inputs reduction)
                collect (compute-kernel-body-aux
                         root
                         input
                         iteration-space
                         transformation))))))

(defmethod compute-kernel-body-aux
    ((root strided-array)
     (reference reference)
     (iteration-space shape)
     (transformation transformation))
  (compute-kernel-body-aux
   root
   (input reference)
   (transform
    (set-intersection iteration-space (shape reference))
    (transformation reference))
   (compose-transformations (transformation reference) transformation)))

(defmethod compute-kernel-body-aux
    ((root strided-array)
     (fusion fusion)
     (iteration-space shape)
     (transformation transformation))
  (let ((input (find iteration-space (inputs fusion)
                     :key #'shape
                     :test #'set-intersectionp)))
    (compute-kernel-body-aux
     root
     input
     (set-intersection iteration-space (shape input))
     transformation)))

(defmethod compute-kernel-body-aux
    ((root strided-array)
     (immediate immediate)
     (iteration-space shape)
     (transformation transformation))
  (error "Something is wrong with the buffer table."))
