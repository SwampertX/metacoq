(* From MetaCoq.Template Require Import All. *)
(* Import MCMonadNotation. *)

Definition a := 0.
Definition b := 1.
Module M.
    (* Print a.
    Fail Print M.a. *)
    Definition a := 1.
    (* Print a.
    Print M.a. *)
    Module N.
        (* Print a.
        Print M.a.
        Fail Module X := M. *)
        Definition a := 2.
        Print b.
        Module O.
            Definition a := 3.
            Print b.
            Definition c := a + a.
            Compute c.
        End O.
    End N.
    Module X := N.
    Fail Definition a := 2.
End M.

Module M': .
    Definition a := 1.
End M'.

Module M.
    MetaCoq Quote Recursively Definition a := 0.
    Print a.
    Module N.
        MetaCoq Quote Recursively Definition b := 0.
        Print b. (* should see a, b in env *)
        Check a.
        Module N1.
            MetaCoq Quote Recursively Definition b := 0.
            Print b. (* should see a, b in env *)
            Check a.
        End N1.
    End N.
    MetaCoq Quote Recursively Definition c := 0.
    Print c. (* should see a in env *)
End M.

Module N := M.


MetaCoq Run (tmQuoteModule "M"%bs >>= tmPrint).
MetaCoq Run (tmQuoteModule "N"%bs >>= tmPrint).

MetaCoq Quote Recursively Definition a := 0.

Module MM := M.
MetaCoq Run (tmQuoteModule "MM"%bs >>= tmPrint).

Print a.

Module M1.
    Definition b1 := 0.

    MetaCoq Quote Recursively Definition a := 0.
    Print a.
    Module N1.
    End N1.
    MetaCoq Test Quote "N1"%bs.
    Module M := N1.
    MetaCoq Test Quote "M"%bs.


    Definition div (n m: nat) := exists d: nat, d * n = m.
    Definition div_strict (a b: nat) := (div a b) /\ (a <> b). (* Strict partial order *)
    Theorem one_div_everything (n: nat): div 1 n.
    Proof.
        induction n. now exists 0.
        now exists (S n).
    Qed.

    Definition b2 := true.

    Module N2.
        MetaCoq Quote Recursively Definition c := 100.
        Print c.
    End N2.

End M1.
