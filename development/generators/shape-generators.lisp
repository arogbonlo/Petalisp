;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp-development)

(defgenerator shape (&key (dimension 3) (max-size 30) (max-extent 100) intersecting)
  (assert (or (not intersecting)
              (= dimension (dimension intersecting))))
  (let ((range-generators
          (if intersecting
              (mapcar (lambda (range)
                        (make-generator 'range :max-size max-size
                                               :max-extent max-extent
                                               :intersecting range))
                      (ranges intersecting))
              (make-list dimension :initial-element
                         (make-generator 'range :max-size max-size
                                                :max-extent max-extent)))))
    (lambda ()
      (shape-from-ranges
       (mapcar #'funcall range-generators)))))
