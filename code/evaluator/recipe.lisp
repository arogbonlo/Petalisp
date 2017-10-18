;;; © 2016-2017 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

;;; The recipe of a kernel is used both as a blueprint of some
;;; performance-critical function and as a key to search whether such a
;;; function has already been generated and compiled. The latter case is
;;; expected to be far more frequent, so the primary purpose of a recipe is
;;; to select an existing function as fast as possible and without
;;; consing.

(defmacro define-recipe-grammar (&body definitions)
  `(progn
     ,@(iterate
         (for definition in definitions)
         (destructuring-bind (name &key ((:= lambda-list)) &allow-other-keys) definition
           (when lambda-list
             (let* ((variadic? (eq (last-elt lambda-list) '*))
                    (lambda-list (if variadic? (butlast lambda-list) lambda-list)))
               (collect
                   `(defun ,name ,lambda-list
                      ,(if variadic?
                           `(list* ',name ,@lambda-list)
                           `(list ',name ,@lambda-list))))
               (collect
                   `(defun ,(symbolicate name "?") (x)
                      (and (consp x) (eq (car x) ',name))))))))))

;;; The grammar of a recipe is:

(define-recipe-grammar
  (%recipe     := (range-info* target-info* source-info* expression))
  (%reference  := (%source-or-%target %index *))
  (%store      := (%reference expression))
  (%call       := (operator expression *))
  (%reduce     := (%range operator expression))
  (%accumulate := (%range operator initial-value expression))
  (%for        := (%range expression))
  (%index      :? (cons symbol (cons rational (cons rational null))))
  (%source     :? symbol)
  (%target     :? symbol)
  (%range      :? symbol)
  (expression  :? (or %reference %store %call %reduce %accumulate %for))
  (range-info  :? (cons (integer 0 *) (cons (integer 0 *) (cons (integer 1 *) null))))
  (target-info :? petalisp-type-specifier)
  (source-info :? petalisp-type-specifier))

(define-symbol-pool %source "S")
(define-symbol-pool %target "T")
(define-symbol-pool %index  "I")
(define-symbol-pool %range  "R")

(defgeneric %indices (transformation)
  (:method ((transformation identity-transformation))
    (let ((dimension (input-dimension transformation))
          (zeros '(0 0)))
      (with-vector-memoization (dimension)
        (iterate
          (for index from (1- dimension) downto 0)
          (collect (cons (%index index) zeros) at beginning)))))
  (:method ((transformation affine-transformation))
    (iterate
      (for column in-vector (spm-column-indices (linear-operator transformation)) downto 0)
      (for value in-vector (spm-values (linear-operator transformation)) downto 0)
      (for offset in-vector (translation-vector transformation) downto 0)
      (collect (list (%index column) value offset) at beginning))))

;; ugly
(defun zero-based-transformation (index-space)
  (let* ((ranges (ranges index-space))
         (dimension (length ranges)))
    (make-affine-transformation
     (make-array dimension :initial-element nil)
     (scaled-permutation-matrix
      dimension dimension
      (apply #'vector (iota dimension))
      (map 'vector #'range-step ranges))
     (map 'vector #'range-start ranges))))

(defun range-information (range)
  (let ((min-size (size range))
        (max-size (size range))
        (step (range-step range)))
    (list min-size max-size step)))

(defun map-recipes (function data-structure &key (leaf-test #'immediate?))
  "Invoke FUNCTION for every recipe that computes values of DATA-STRUCTURE
   and references data-structures that satisfy LEAF-TEST.

   For every recipe, FUNCTION receives the following arguments:
   1. the recipe
   2. the index space computed by the recipe
   3. a vector of all referenced ranges
   4. a vector of all referenced data-structures"
  (let ((recipe-iterator
          (recipe-iterator
           leaf-test
           data-structure
           (index-space data-structure)
           (make-identity-transformation (dimension data-structure)))))
    (handler-case
        (loop (multiple-value-call function (funcall recipe-iterator)))
      (iterator-exhausted () (values)))))

;; the iterator should be factored out as a separate utility...
(define-condition iterator-exhausted () ())

(defvar *recipe-iteration-space* nil)
(defvar *recipe-ranges* nil)
(defvar *recipe-sources* nil)

(defun recipe-iterator (leaf-test node relevant-space transformation)
  (let ((body-iterator (recipe-body-iterator leaf-test node relevant-space transformation)))
    (λ (let ((*recipe-iteration-space* (index-space node))
             (*recipe-ranges*  (copy-array (ranges relevant-space) :fill-pointer t))
             (*recipe-sources* (make-array 6 :fill-pointer 0)))
         (let* ((body (funcall body-iterator)))
           (iterate
             (for index from (1- (length *recipe-ranges*)) downto 0)
             (setf body (%for (%range index) body)))
           (values
            (%recipe
             (map 'vector #'range-information *recipe-ranges*)
             (vector (element-type node))
             (map 'vector #'element-type *recipe-sources*)
             body)
            *recipe-iteration-space*
            *recipe-ranges*
            *recipe-sources*))))))

(defun recipe-body-iterator (leaf-test node relevant-space transformation)
  (cond
    ;; convert leaf nodes to an iterator with a single value
    ((funcall leaf-test node)
     (let ((first-visit? t))
       (λ (if first-visit?
              (let ((source
                      (%source (or (position node *recipe-sources*)
                                   (vector-push-extend node *recipe-sources*)))))
                (setf first-visit? nil)
                (%reference source (%indices transformation)))
              (signal 'iterator-exhausted)))))
    ;; application nodes simply call the iterator of each input
    ((application? node)
     (let ((input-iterators
             (map 'vector
                  (λ input (recipe-body-iterator leaf-test input relevant-space transformation))
                  (inputs node))))
       (λ `(%call ,(operator node) ,@(map 'list #'funcall input-iterators)))))
    ;; reference nodes are eliminated entirely
    ((reference? node)
     (let* ((new-transformation (composition (transformation node) transformation))
            (new-relevant-space (intersection relevant-space (index-space node))))
       (recipe-body-iterator leaf-test (input node) new-relevant-space new-transformation)))
    ((reduction? node)
     (error "TODO"))
    ;; fusion nodes are eliminated by path replication. This replication
    ;; process is the only reason why we use tree iterators. A fusion node
    ;; with N inputs returns an iterator returning N recipes.
    ((fusion? node)
     (let* ((max-size (length (inputs node)))
            (iteration-spaces (make-array max-size :fill-pointer 0))
            (input-iterators (make-array max-size :fill-pointer 0)))
       (iterate
         (for input in-sequence (inputs node))
         (for subspace = (index-space input))
         (when-let ((relevant-subspace (intersection relevant-space subspace)))
           (vector-push (funcall (inverse transformation) relevant-subspace)
                        iteration-spaces)
           (vector-push (recipe-body-iterator leaf-test input relevant-subspace transformation)
                        input-iterators)))
       (λ (loop
            (if (= 0 (fill-pointer input-iterators))
                (signal 'iterator-exhausted)
                (handler-case
                    (progn
                      (setf *recipe-iteration-space* (vector-pop iteration-spaces))
                      (return (funcall (vector-pop input-iterators))))
                  (iterator-exhausted ())))))))))

