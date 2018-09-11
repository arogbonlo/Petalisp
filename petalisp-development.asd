(defsystem :petalisp-development
  :description "Developer utilities for the parallel programming library Petalisp."
  :author "Marco Heisig <marco.heisig@fau.de>"
  :license "AGPLv3"

  :depends-on ("petalisp"
               "cl-dot"
               "uiop")
  :in-order-to ((test-op (test-op :petalisp)))

  :serial t
  :components
  ((:module "core"
    :components
    ((:module "graphviz"
      :components
      ((:file "utilities")
       (:file "protocol")
       (:file "strided-arrays")
       (:file "ir")
       (:file "view")))))))
