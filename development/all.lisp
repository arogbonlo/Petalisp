;;;; © 2016-2018 Marco Heisig - licensed under AGPLv3, see the file COPYING     -*- coding: utf-8 -*-

(uiop:define-package :petalisp/development/all
  (:nicknames :petalisp-dev)
  (:use :closer-common-lisp :alexandria :trivia)
  (:use-reexport
   :petalisp/core/api
   :petalisp/development/visualization))
