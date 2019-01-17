;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package :petalisp-development)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Classes

(defclass petalisp-graph (any-graph)
  ())

(defclass petalisp-edge (any-edge)
  ())

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods

(defmethod graphviz-node-attributes
    ((graph petalisp-graph)
     (node t))
  `(:shape :box :style :filled))

(defmethod graphviz-graph-attributes
    ((graph petalisp-graph))
  `())
