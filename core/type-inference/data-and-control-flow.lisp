;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(in-package :petalisp-core)

(define-type-inferrer identity (type)
  (values (list type) nil '() 'identity))
