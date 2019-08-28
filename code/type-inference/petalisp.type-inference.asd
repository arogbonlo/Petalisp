(defsystem "petalisp.type-inference"
  :author "Marco Heisig <marco.heisig@fau.de>"
  :license "AGPLv3"

  :depends-on
  ("alexandria"
   "trivia"
   "trivial-arguments")

  :in-order-to ((test-op (test-op "petalisp.test-suite")))

  :serial t
  :components
  ((:file "packages")
   (:file "auxiliary-types")
   (:file "function-lambda-lists")
   (:file "ntype-1")
   (:file "ntype-2")
   (:file "ntype-3")
   (:file "conditions")
   (:file "special-functions")
   (:file "define-rule")
   (:file "define-instruction")
   (:file "specialize")
   (:module "common-lisp"
    :components
    ((:file "auxiliary")
     (:file "abs")
     (:file "add")
     (:file "casts")
     (:file "cmpeq")
     (:file "cmpneq")
     (:file "cmpx")
     (:file "cos")
     (:file "data-and-control-flow")
     (:file "div")
     (:file "floatp")
     (:file "max")
     (:file "min")
     (:file "minusp")
     (:file "mul")
     (:file "plusp")
     (:file "sin")
     (:file "sub")
     (:file "tan")
     (:file "type-checks")
     (:file "types-and-classes")
     (:file "zerop")))))