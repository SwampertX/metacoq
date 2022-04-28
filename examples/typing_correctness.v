(* Distributed under the terms of the MIT license. *)
From MetaCoq.Template Require Import config Universes Loader.
From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICTyping PCUICLiftSubst.
From MetaCoq.SafeChecker Require Import PCUICErrors PCUICWfEnv PCUICWfEnvImpl PCUICTypeChecker PCUICSafeChecker.
From Equations Require Import Equations.

Local Existing Instance default_checker_flags.
Local Existing Instance PCUICSN.default_normalizing.
Import MCMonadNotation.

(* ********************************************************* *)
(* In this file we define a small plugin which proves        *)
(* the identity theorem for any sort using the safe checker. *)
(* ********************************************************* *)

Definition bAnon := {| binder_name := nAnon; binder_relevance := Relevant |}.
Definition bNamed s := {| binder_name := nNamed s; binder_relevance := Relevant |}.

Definition tImpl X Y := tProd bAnon X (lift0 1 Y).

Definition univ := Level.Level "s".

(* TODO move to SafeChecker *)

Definition gctx : global_env_ext := 
  ({| universes := (LS.union (LevelSet.singleton Level.lzero) (LevelSet.singleton univ), ConstraintSet.empty); declarations := [] |}, Monomorphic_ctx).

(** We use the environment checker to produce the proof that gctx, which is a singleton with only 
    universe "s" declared  is well-formed. *)

Definition kername_of_string (s : string) : kername :=
  (MPfile [], s).

Global Program Instance fake_guard_impl : abstract_guard_impl :=
{| guard_impl := fake_guard_impl |}.
Next Obligation. Admitted.  

Definition make_wf_env_ext (Σ : global_env_ext) : EnvCheck wf_env_ext wf_env_ext :=
  '(exist Σ' pf) <- check_wf_ext optimized_abstract_env_impl Σ ;;
  ret Σ'.

Definition gctx_wf_env : wf_env_ext.
Proof.
  let wf_proof := eval hnf in (make_wf_env_ext gctx) in 
  match wf_proof with
  | CorrectDecl _ ?x => exact x
  | _ => fail "Couldn't prove the global environment is well-formed"
  end.
Defined.



(** There is always a proof of `forall x : Sort s, x -> x` *)

Definition inh {cf:checker_flags} (Σ : wf_env_ext) Γ T := ∑ t, forall Σ0 : global_env_ext, abstract_env_ext_rel Σ Σ0 -> ∥ typing Σ0 Γ t T ∥.

Definition check_inh (Σ : wf_env_ext) Γ (wfΓ : forall Σ0 : global_env_ext, abstract_env_ext_rel Σ Σ0 -> ∥ wf_local Σ0 Γ ∥) t {T} : typing_result (inh Σ Γ T) := 
  prf <- check_type_wf_env_fast optimized_abstract_env_impl Σ Γ wfΓ t (T := T) ;;
  ret (t; prf).

Ltac fill_inh t := 
  lazymatch goal with
  [ wfΓ : forall _ _, ∥ wf_local _ ?Γ ∥ |- inh ?Σ ?Γ ?T ] => 
    let t := uconstr:(check_inh Σ Γ wfΓ t (T:=T)) in
    let proof := eval cbn in t in
    match proof with
    | Checked ?d => exact_no_check d
    | TypeError ?e => 
        let str := eval cbn in (string_of_type_error Σ e) in
        fail "Failed to inhabit " T " : " str
    | _ => set (blocked := proof)
    (* fail "Anomaly: unexpected return value: " proof *)
    end
  | [ |- inh _ ?Γ _ ] => fail "Missing local wellformedness assumption for" Γ
  end.

(* Lemma identity_typing (u := Universe.make univ): inh gctx_wf_env [] (tImpl (tSort u) (tSort u)).
Proof.
  set (impl := tLambda (bNamed "s") (tSort u) (tRel 0)).
  assert (wfΓ : forall Σ0 : global_env_ext,
  abstract_env_ext_rel gctx_wf_env Σ0 -> ∥ wf_local Σ0 [] ∥) by do 2 constructor.

  Time fill_inh impl.

Time Qed. *)


Lemma identity_typing (u := Universe.make univ): 
typing_result
     (∑ t : term,
        forall Σ0 : global_env_ext,
        Σ0 =
        ({|
           universes :=
             (LS.union (LevelSet.singleton Level.lzero)
                (LevelSet.singleton univ), ConstraintSet.empty);
           declarations := []
         |}, Monomorphic_ctx) ->
        ∥ Σ0;;; [] |- t
          : tProd (bNamed "s") (tSort u) (tImpl (tRel 0) (tRel 0)) ∥).
(* inh gctx_wf_env [] (tProd (bNamed "s") (tSort u) (tImpl (tRel 0) (tRel 0))). *)
Proof.
  set (impl := tLambda (bNamed "s") (tSort u) (tLambda bAnon (tRel 0) (tRel 0))).
  assert (wfΓ : forall Σ0 : global_env_ext,
  abstract_env_ext_rel gctx_wf_env Σ0 -> ∥ wf_local Σ0 [] ∥) by do 2 constructor.
  pose (T := tProd (bNamed "s") (tSort u) (tImpl (tRel 0) (tRel 0))).
  pose (Σ := gctx_wf_env).
  let t := uconstr:(check_inh Σ [] wfΓ impl (T:=T)) in
  let proof := eval cbn in t in
  match proof with
  | Checked ?d => exact_no_check d
  | TypeError ?e => 
      let str := eval cbn in (string_of_type_error Σ e) in
      fail "Failed to inhabit " T " : " str
  | _ => set (blocked := proof)
  (* fail "Anomaly: unexpected return value: " proof *)
  end.
  exact blocked. 
Defined. 

(* Print Opaque Dependencies identity_typing. *)
