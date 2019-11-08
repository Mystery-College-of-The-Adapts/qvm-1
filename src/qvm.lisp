;;;; src/qvm.lisp
;;;;
;;;; Author: Robert Smith

(in-package #:qvm)


(defclass base-qvm (classical-memory-mixin)
  ((number-of-qubits :reader number-of-qubits
                     :initarg :number-of-qubits
                     :type alexandria:non-negative-fixnum
                     :initform (error ":NUMBER-OF-QUBITS is a required initarg ~ 
                                       to BASE-QVM.")
                     :documentation "Number of qubits being simulated by the QVM.")
   (state :accessor state
          :initarg :state
          :documentation "The unpermuted wavefunction in standard order.")
   (program-compiled-p :accessor program-compiled-p
                       :initform nil
                       :documentation "Has the loaded program been compiled?"))
  (:metaclass abstract-class))


(defclass pure-state-qvm (base-qvm)
  ((state :accessor state
          :initarg :state
          :type (or null pure-state)
          :documentation "The unpermuted wavefunction in standard order."))
  (:documentation "An pure-state implementation of the Quantum Abstract Machine."))

(defmethod amplitudes ((qvm pure-state-qvm))
  (amplitudes (state qvm)))

(defmethod (setf amplitudes) (new-amplitudes (qvm pure-state-qvm) )
  (setf (amplitudes (state qvm)) new-amplitudes))
;;; Creation and Initialization

(defmethod initialize-instance :after ((qvm pure-state-qvm) &rest args)
  (declare (ignore args))
  (let ((num-qubits (number-of-qubits qvm)))
    (cond
      ((and (slot-boundp qvm 'state)
            (not (null (slot-value qvm 'state))))
       ;; Check that it represents the number of qubits it should.
       (assert (<= num-qubits (wavefunction-qubits (amplitudes qvm)))
               ()
               "The provided amplitudes to the PURE-STATE-QVM ~A represents ~D qubit~:P, ~
                but the QAM is specified to need ~D qubit~:P."
               qvm
               (wavefunction-qubits (amplitudes (state qvm)))
               num-qubits))
      (t
       ;; If the amplitudes weren't specified, initialize to |...000>.
       ;;
       ;; We explicitly zero out the memory to make sure all pages get
       ;; touched.
       (setf (state qvm) (make-instance 'pure-state :num-qubits (number-of-qubits qvm)))
       (bring-to-zero-state (amplitudes qvm))))))


(defun make-qvm (num-qubits &key (classical-memory-model quil:**empty-memory-model**)
                                 (allocation nil))
  "Make a new quantum virtual machine with NUM-QUBITS number of qubits and a classical memory size of CLASSICAL-MEMORY-SIZE bits.

ALLOCATION is an optional argument with the following behavior.

    - If it's NULL (default), then a standard wavefunction in the Lisp heap will be allocated.

    - If it's a STRING, then the wavefunction will be allocated as a shared memory object, accessible by that name.

    - Otherwise, it's assumed to be an object that is compatible with the ALLOCATION-LENGTH and ALLOCATE-VECTOR methods
"
  (check-type num-qubits unsigned-byte)
  (check-type classical-memory-model quil:memory-model)
  (make-instance 'pure-state-qvm
                 :number-of-qubits num-qubits
                 :state (make-pure-state num-qubits :allocation allocation)
                 :classical-memory-subsystem
                 (make-instance 'classical-memory-subsystem
                                :classical-memory-model
                                classical-memory-model)))


(defmethod compile-loaded-program ((qvm pure-state-qvm))
  "Compile the loaded program on the PURE-STATE-QVM QVM."
  (unless (program-compiled-p qvm)
    (when *fuse-gates-during-compilation*
      (setf (program qvm) (quil::fuse-gates-in-executable-code (program qvm))))
    (when *compile-measure-chains*
      (setf (program qvm) (compile-measure-chains (program qvm) (number-of-qubits qvm))))
    (setf (program qvm)
          (map 'vector (lambda (isn) (compile-instruction qvm isn)) (program qvm)))
    (setf (program-compiled-p qvm) t))
  qvm)

;;; Fundamental Manipulation of the QVM


(defun nth-amplitude (qvm n)
  "Get the Nth amplitude of the quantum virtual machine QVM."
  (aref (amplitudes qvm) n))

(defun (setf nth-amplitude) (new-value qvm n)
  "Set the Nth amplitude of the quantum virtual machine QVM."
  (setf (aref (amplitudes qvm) n) new-value))

(defun map-amplitudes (qvm f)
  "Apply the function F to the amplitudes of the quantum virtual machine QVM in standard order."
  (map nil f (amplitudes qvm))
  (values))

(defmethod reset-quantum-state ((qvm pure-state-qvm))
  ;; We don't reset the classical state because that memory could be
  ;; shared.
  (bring-to-zero-state (amplitudes qvm))
  qvm)

;;; DEPRECATED:

(defun qubit-probability (qvm qubit)
  "DEPRECATED // The probability that the physical qubit addressed by QUBIT is 1."
  (let ((wavefunction (amplitudes qvm)))
    (declare (type quantum-state wavefunction))
    (wavefunction-excited-state-probability wavefunction qubit)))
