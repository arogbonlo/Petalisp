(in-package :common-lisp-user)

(defpackage #:petalisp.examples.machine-learning
  (:use
   #:common-lisp
   #:petalisp)
  (:export
   #:trainable-parameter
   #:softmax
   #:relu
   #:make-fully-connected-layer
   #:make-convolutional-layer
   #:make-maxpool-layer))

(in-package #:petalisp.examples.machine-learning)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Trainable Parameters

(defclass trainable-parameter (parameter)
  ((%value :initarg :value :accessor trainable-parameter-value)))

(defun make-trainable-parameter (initial-value)
  (let ((value (lazy-array initial-value)))
    (make-instance 'trainable-parameter
      :shape (shape initial-value)
      :element-type (element-type value)
      :value value)))

(declaim (inline trainable-parameter-p))
(defun trainable-parameter-p (object)
  (typep object 'trainable-parameter))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Machine Learning Building Blocks

(defun make-random-array (dimensions &key (element-type 't))
  (let ((array (make-array dimensions :element-type element-type)))
    (loop for index below (array-total-size array) do
      (setf (row-major-aref array index)
            (1- (random (coerce 2 (array-element-type array))))))
    array))

(defun softmax (array)
  (let ((totals (α #'exp array)))
    (α #'/ totals (β* #'+ 0 totals))))

(defun relu (array)
  (α #'max (coerce 0 (element-type array)) array))

(defun make-fully-connected-layer (array output-shape)
  (let* ((m (total-size output-shape))
         (n (total-size array))
         (weights
           (make-trainable-parameter
            (α #'/ (make-random-array (list m n) :element-type (element-type array)) m)))
         (biases
           (make-trainable-parameter
            (α #'/ (make-random-array m :element-type (element-type array)) m))))
    (reshape
     (α #'+
        (β #'+
           (α #'*
              (reshape weights (τ (m n) (n m)))
              (reshape (flatten array) (τ (n) (n 0)))))
        biases)
     output-shape)))

(define-modify-macro minf (&rest numbers) min)
(define-modify-macro maxf (&rest numbers) max)

(defun make-convolutional-layer (array &key (stencil '()) (n-filters 1))
  (let* ((k (rank array))
         (lower-bounds (make-array k :initial-element 0))
         (upper-bounds (make-array k :initial-element 0))
         (filters
           (make-trainable-parameter
            (make-random-array n-filters :element-type (element-type array))))
         (d nil))
    ;; Determine the dimension of the stencil.
    (loop for offsets in stencil do
      (if (null d)
          (setf d (length offsets))
          (assert (= (length offsets) d))))
    ;; Determine the bounding box of the stencil.
    (loop for offsets in stencil do
      (loop for offset in offsets
            for index from (- k d) do
              (minf (aref lower-bounds index) offset)
              (maxf (aref upper-bounds index) offset)))
    ;; Use the bounding box to compute the shape of the result.
    (let ((result-shape
            (make-shape
             (list*
              (range 0)
              (loop for lb across lower-bounds
                    for ub across upper-bounds
                    for range in (shape-ranges (shape array))
                    collect
                    (if (and (integerp lb)
                             (integerp ub))
                        (let ((lo (- (range-start range) lb))
                              (hi (- (range-end range) ub)))
                          (assert (< lo hi))
                          (range lo hi))
                        range))))))
      ;; Compute the result.
      (collapse
       (apply #'α #'+
              (loop for offsets in stencil
                    collect
                    (α #'*
                       (reshape
                        filters
                        (make-transformation :input-rank 1 :output-rank (1+ k)))
                       (reshape
                        array
                        (make-transformation :offsets (mapcar #'- offsets))
                        result-shape))))))))

(defun make-maxpool-layer (array pooling-factors)
  (let* ((pooling-factors (coerce pooling-factors 'vector))
         (array (lazy-array array))
         (pooling-ranges
           (loop for pooling-factor across pooling-factors
                 for range in (shape-ranges (shape array))
                 for index from 1 do
                   (check-type pooling-factor (integer 1 *) "a positive integer")
                   (unless (zerop (mod (range-size range) pooling-factor))
                     (error "~@<The ~:R range of the shape ~S is not ~
                         divisible by the corresponding pooling factor ~S.~:@>"
                            index (shape array) pooling-factor))
                 collect
                 (loop for offset below pooling-factor
                       collect
                       (range (+ (range-start range) offset)
                              (* (range-step range) pooling-factor)
                              (range-end range))))))
    (collapse
     (apply #'α #'max
            (apply #'alexandria:map-product
                   (lambda (&rest ranges)
                     (reshape array (make-shape ranges)))
                   pooling-ranges)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Training

(defun train (network &rest training-data-plist &key learning-rate &allow-other-keys)
  (let* ((outputs (network-outputs network))
         (parameters (network-parameters network))
         (trainable-parameters (remove-if-not #'trainable-parameter-p parameters))
         (gradient (differentiator outputs trainable-parameters))
         (training-network
           (apply #'make-network
                  (loop for trainable-parameter in trainable-parameters
                        collect
                        (α #'+ trainable-parameter
                           (α #'* learning-rate (funcall gradient trainable-parameter))))))
         (n nil))
    ;; Determine the training data size.
    (alexandria:doplist (parameter data training-data-plist) ()
      (unless (symbolp parameter)
        (if (null n)
            (setf n (range-size (first (shape-ranges (shape data)))))
            (assert (= n (range-size (first (shape-ranges (shape data)))))))))
    ;; Iterate over the training data.
    (loop for index below n do
      ;; Assemble the arguments.
      (let ((args '()))
        ;; Training data.
        (alexandria:doplist (parameter data training-data-plist)
            (unless (symbolp parameter)
              (push (reshape
                     data
                     (make-shape
                      (list*
                       (range index)
                       (rest (shape-ranges (shape data)))))
                     (make-transformation
                      :input-mask (list* index (make-list (1- (rank data))))
                      :output-mask (alexandria:iota (1- (rank data)) :start 1)))
                    args)
              (push parameter args)))
        (dolist (trainable-parameter trainable-parameters)
          (push (trainable-parameter-value trainable-parameter) args)
          (push trainable-parameter args))
        ;; Update all trainable parameters.
        (loop for trainable-parameter in trainable-parameters
              for value in (apply #'call-network training-network (reverse args))
              do (setf (trainable-parameter-value trainable-parameter)
                       value))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Classification of MNIST Data

;;; Note: We only ship a very small sample of the MNIST data with Petalisp,
;;; so learning efforts will not be too good.  If you want to run serious
;;; tests, you should replace these paths with paths to the full MNIST
;;; data.

(defun load-array (&rest path)
  (numpy-file-format:load-array
   (asdf:component-pathname
    (asdf:find-component
     (asdf:find-system "petalisp.examples")
     path))))

(defparameter *train-images* (load-array "mnist-data" "train-images.npy"))
(defparameter *train-labels* (load-array "mnist-data" "train-labels.npy"))
(defparameter *test-images* (load-array "mnist-data" "test-images.npy"))
(defparameter *test-labels* (load-array "mnist-data" "test-labels.npy"))

(defun main ()
  (let* ((input (make-instance 'parameter
                  :shape (~ 1 28 ~ 1 28)
                  :element-type 'single-float))
         (output
           (make-fully-connected-layer
            (make-maxpool-layer
             (relu
              (make-convolutional-layer
               input
               :stencil '((0 0) (1 0) (0 1) (-1 0) (0 -1))
               :n-filters 12))
             '(1 2 2))
            (~ 0 9))))
    (train (make-network output)
           :learning-rate 0.02
           input (α #'/ *train-images* 255.0)
           output (α 'coerce
                     (α (lambda (n i) (if (= n i) 1.0 0.0))
                        (reshape *train-labels* (τ (i) (i 0)))
                        #(0 1 2 3 4 5 6 7 8 9))
                     'single-float))))