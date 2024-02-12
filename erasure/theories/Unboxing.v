(* Distributed under the terms of the MIT license. *)
From Coq Require Import Utf8 Program.
From MetaCoq.Utils Require Import utils.
From MetaCoq.Common Require Import config Kernames Primitive BasicAst EnvMap.
From MetaCoq.Erasure Require Import EPrimitive EAst EAstUtils EInduction EArities
    ELiftSubst ESpineView EGlobalEnv EWellformed EEnvMap
    EWcbvEval EEtaExpanded ECSubst EWcbvEvalEtaInd EProgram.

Local Open Scope string_scope.
Set Asymmetric Patterns.
Import MCMonadNotation.

From Equations Require Import Equations.
Set Equations Transparent.
Local Set Keyed Unification.
From Coq Require Import ssreflect ssrbool.

(** We assume [Prop </= Type] and universes are checked correctly in the following. *)
Local Existing Instance extraction_checker_flags.

Ltac introdep := let H := fresh in intros H; depelim H.

#[global]
Hint Constructors eval : core.

Import MCList (map_InP, map_InP_spec).

Equations safe_hd {A} (l : list A) (nnil : l <> nil) : A :=
| [] | nnil := False_rect _ (nnil eq_refl)
| hd :: _ | _nnil := hd.

Section optimize.
  Context (Σ : GlobalContextMap.t).

  Section Def.
  Import TermSpineView.


  Definition unboxable (idecl : one_inductive_body) (cdecl : constructor_body) :=
    (#|idecl.(ind_ctors)| == 1) && (cdecl.(cstr_nargs) == 1).

  Equations is_unboxable (kn : inductive) (c : nat) : bool :=
    | kn | 0 with GlobalContextMap.lookup_constructor Σ kn 0 := {
      | Some (mdecl, idecl, cdecl) := unboxable idecl cdecl
      | None := false }
    | kn | S _ := false.


  Notation " t 'eqn:' h " := (exist t h) (only parsing, at level 12).
  Import Equations.Prop.Logic.

  Opaque is_unboxable.

  Equations get_unboxable_case_branch (ind : inductive) (brs : list (list name * term)) : option (name * term) :=
  get_unboxable_case_branch ind [([brna], bbody)] := Some (brna, bbody);
  get_unboxable_case_branch ind _ := None.

  Lemma get_unboxable_case_branch_spec {ind : inductive} {brs : list (list name * term)} {brna bbody} :
    get_unboxable_case_branch ind brs = Some (brna, bbody) ->
    brs = [([brna], bbody)].
  Proof.
    funelim (get_unboxable_case_branch ind brs) => //.
    now intros [= <- <-].
  Qed.

  Equations? optimize (t : term) : term
    by wf t (fun x y : EAst.term => size x < size y) :=
  | e with TermSpineView.view e := {
    | tRel i => EAst.tRel i
    | tEvar ev args => EAst.tEvar ev (map_InP args (fun x H => optimize x))
    | tLambda na M => EAst.tLambda na (optimize M)
    | tApp u v napp nnil with construct_viewc u := {
      | view_construct kn c block_args with is_unboxable kn c :=
        { | true => optimize (safe_hd v nnil)
          | false => mkApps (EAst.tConstruct kn c block_args) (map_InP v (fun x H => optimize x)) }
      | view_other u nconstr =>
        mkApps (optimize u) (map_InP v (fun x H => optimize x))
    }
    | tLetIn na b b' => EAst.tLetIn na (optimize b) (optimize b')
    | tCase ind c brs with inspect (is_unboxable ind.1 0) =>
      { | true eqn:unb with inspect (get_unboxable_case_branch ind.1 brs ) := {
          | Some (brna, bbody) eqn:heqbr => EAst.tLetIn brna (optimize c) (optimize bbody)
          | None eqn:heqbr :=
            let brs' := map_InP brs (fun x H => (x.1, optimize x.2)) in
            EAst.tCase ind (optimize c) brs' }
        | false eqn:unb :=
            let brs' := map_InP brs (fun x H => (x.1, optimize x.2)) in
            EAst.tCase ind (optimize c) brs' }
    | tProj p c with inspect (is_unboxable p.(proj_ind) 0) := {
        | true eqn:unb => optimize c
        | false eqn:unb => EAst.tProj p (optimize c) }
    | tConstruct ind n args => EAst.tConstruct ind n args
    | tFix mfix idx =>
      let mfix' := map_InP mfix (fun d H => {| dname := dname d; dbody := optimize d.(dbody); rarg := d.(rarg) |}) in
      EAst.tFix mfix' idx
    | tCoFix mfix idx =>
      let mfix' := map_InP mfix (fun d H => {| dname := dname d; dbody := optimize d.(dbody); rarg := d.(rarg) |}) in
      EAst.tCoFix mfix' idx
    | tBox => EAst.tBox
    | tVar n => EAst.tVar n
    | tConst n => EAst.tConst n
    | tPrim p => EAst.tPrim (map_primIn p (fun x H => optimize x)) }.
  Proof.
    all:try lia.
    all:try apply (In_size); tea.
    - eapply (In_size id size) in H. unfold id in H.
      change (fun x => size x) with size in *. lia.
    - rewrite size_mkApps. destruct v; cbn => //. lia.
    - rewrite size_mkApps.
      eapply (In_size id size) in H. change (fun x => size (id x)) with size in H. unfold id in H.  cbn. lia.
    - rewrite size_mkApps. destruct v => //=. lia.
    - rewrite size_mkApps.
      eapply (In_size id size) in H. change (fun x => size (id x)) with size in H. unfold id in H.  cbn. lia.
    - move/get_unboxable_case_branch_spec: heqbr => -> //=. lia.
    - eapply (In_size snd size) in H; cbn in H; lia.
    - eapply (In_size snd size) in H; cbn in H; lia.
    - eapply (In_size dbody size) in H; cbn in H; lia.
    - eapply (In_size dbody size) in H; cbn in H; lia.
    - destruct p as [? []]; cbn in H; eauto.
      intuition auto; subst; cbn; try lia.
      eapply (In_size id size) in H0. unfold id in H0.
      change (fun x => size x) with size in H0. lia.
  Qed.
  End Def.

  #[universes(polymorphic)] Hint Rewrite @map_primIn_spec @map_InP_spec : optimize.

  Lemma map_repeat {A B} (f : A -> B) x n : map f (repeat x n) = repeat (f x) n.
  Proof using Type.
    now induction n; simpl; auto; rewrite IHn.
  Qed.

  Lemma map_optimize_repeat_box n : map optimize (repeat tBox n) = repeat tBox n.
  Proof using Type. now rewrite map_repeat. Qed.

  Arguments eqb : simpl never.

  Opaque optimize_unfold_clause_1.
  Opaque optimize.
  Opaque isEtaExp.
  Opaque isEtaExp_unfold_clause_1.

  Lemma closedn_mkApps k f l : closedn k (mkApps f l) = closedn k f && forallb (closedn k) l.
  Proof using Type.
    induction l in f |- *; cbn; auto.
    - now rewrite andb_true_r.
    - now rewrite IHl /= andb_assoc.
  Qed.

  Lemma closed_optimize t k : closedn k t -> closedn k (optimize t).
  Proof using Type Σ.
    funelim (optimize t); simp optimize; rewrite -?optimize_equation_1; toAll; simpl;
    intros; try easy;
    rewrite -> ?map_map_compose, ?compose_on_snd, ?compose_map_def, ?map_length;
    unfold test_def in *;
    simpl closed in *;
    try solve [simpl; subst; simpl closed; f_equal; auto; rtoProp; solve_all; solve_all]; try easy.
    - solve_all_k 6.
    - rewrite !closedn_mkApps in H1 *.
      rtoProp; intuition auto.
      solve_all.
    - rewrite !closedn_mkApps /= in H0 *. rtoProp.
      destruct v => //=. cbn in H1. rtoProp; intuition auto.
    - rewrite !closedn_mkApps /= in H0 *. rtoProp. repeat solve_all.
    - rtoProp; intuition auto. clear H1 H2 Heq.
      move: H4; move/get_unboxable_case_branch_spec: heqbr => -> //=.
      now rewrite andb_true_r.
  Qed.

  Hint Rewrite @forallb_InP_spec : isEtaExp.
  Transparent isEtaExp_unfold_clause_1.

  Local Lemma optimize_mkApps_nonnil f v (nnil : v <> []):
    ~~ isApp f ->
    optimize (mkApps f v) = match construct_viewc f with
      | view_construct kn c block_args =>
         if is_unboxable kn c then optimize (safe_hd v nnil)
         else mkApps (EAst.tConstruct kn c block_args) (map optimize v)
      | view_other u nconstr => mkApps (optimize f) (map optimize v)
    end.
  Proof using Type.
    intros napp. rewrite optimize_equation_1.
    destruct (TermSpineView.view_mkApps (TermSpineView.view (mkApps f v)) napp nnil) as [hna [hv' ->]].
    simp optimize; rewrite -optimize_equation_1.
    destruct (construct_viewc f).
    2:cbn; simp optimize => //.
    simp optimize.
    destruct (is_unboxable ind n) => //=. simp optimize.
    replace (safe_hd v hv') with (safe_hd v nnil) => //.
    destruct v; cbn => //.
    f_equal. now simp optimize.
  Qed.

  Lemma optimize_mkApps f v : ~~ isApp f ->
    optimize (mkApps f v) = match construct_viewc f with
      | view_construct kn c block_args =>
        if is_unboxable kn c then
          match v with
          | hd :: _ => optimize hd
          | _ => mkApps (EAst.tConstruct kn c block_args) (map optimize v)
          end
        else mkApps (EAst.tConstruct kn c block_args) (map optimize v)
      | view_other u nconstr => mkApps (optimize f) (map optimize v)
    end.
  Proof using Type.
    intros napp.
    destruct v using rev_case; simpl.
    - destruct construct_viewc => //. simp optimize.
      destruct is_unboxable => //.
    - rewrite (optimize_mkApps_nonnil f (v ++ [x])) => //.
      destruct construct_viewc => //.
      destruct is_unboxable eqn:unb => //.
      destruct v eqn:hc => //=.
  Qed.

  Lemma lookup_inductive_pars_constructor_pars_args {ind n pars args} :
    lookup_constructor_pars_args Σ ind n = Some (pars, args) ->
    lookup_inductive_pars Σ (inductive_mind ind) = Some pars.
  Proof using Type.
    rewrite /lookup_constructor_pars_args /lookup_inductive_pars.
    rewrite /lookup_constructor /lookup_inductive. destruct lookup_minductive => //.
    cbn. do 2 destruct nth_error => //. congruence.
  Qed.

  Lemma optimize_csubst a k b :
    closed a ->
    isEtaExp Σ a ->
    isEtaExp Σ b ->
    optimize (ECSubst.csubst a k b) = ECSubst.csubst (optimize a) k (optimize b).
  Proof using Type.
    intros cla etaa; move cla before a. move etaa before a.
    funelim (optimize b); cbn; simp optimize isEtaExp; rewrite -?isEtaExp_equation_1 -?optimize_equation_1; toAll; simpl;
    intros; try easy;
    rewrite -> ?map_map_compose, ?compose_on_snd, ?compose_map_def, ?map_length;
    unfold test_def in *;
    simpl closed in *; try solve [simpl subst; simpl closed; f_equal; auto; rtoProp; solve_all]; try easy.

    - destruct Nat.compare => //.
    - f_equal. rtoProp. solve_all. destruct args; inv H0. eauto.
    - f_equal. solve_all.  move/andP: b => [] _ he. solve_all.
    - specialize (H a etaa cla k).
      rewrite !csubst_mkApps in H1 *.
      rewrite isEtaExp_mkApps_napp // in H1.
      destruct construct_viewc.
      * cbn. rewrite optimize_mkApps //.
      * move/andP: H1 => [] et ev.
        rewrite -H //.
        assert (map (csubst a k) v <> []).
        { destruct v; cbn; congruence. }
        pose proof (etaExp_csubst Σ _ k _ etaa et).
        destruct (isApp (csubst a k t)) eqn:eqa.
        { destruct (decompose_app (csubst a k t)) eqn:eqk.
          rewrite (decompose_app_inv eqk) in H2 *.
          pose proof (decompose_app_notApp _ _ _ eqk).
          assert (l <> []).
          { intros ->. rewrite (decompose_app_inv eqk) in eqa. now rewrite eqa in H3. }
          rewrite isEtaExp_mkApps_napp // in H2.
          assert ((l ++ map (csubst a k) v)%list <> []).
          { destruct l; cbn; congruence. }

          destruct (construct_viewc t0) eqn:hc.
          { rewrite -mkApps_app /=.
            rewrite optimize_mkApps // optimize_mkApps //.
            cbn -[lookup_inductive_pars].
            move/andP: H2 => [] ise hl.
            unfold isEtaExp_app in ise.
            destruct is_unboxable eqn:isunb => //.
            destruct l => //=.
            rewrite (lookup_inductive_pars_constructor_pars_args eqpars).
            rewrite -mkApps_app /= !skipn_map. f_equal.
            rewrite skipn_app map_app. f_equal.
            assert (pars - #|l| = 0). rtoProp. rename H2 into ise. eapply Nat.leb_le in ise; lia.
            rewrite H2 skipn_0.
            rewrite !map_map_compose.
            clear -etaa cla ev H0. solve_all. }
          { rewrite -mkApps_app.
            rewrite optimize_mkApps //. rewrite hc.
            rewrite optimize_mkApps // hc -mkApps_app map_app //.
            f_equal. f_equal.
            rewrite !map_map_compose.
            clear -etaa cla ev H0. solve_all. } }
        { rewrite optimize_mkApps ?eqa //.
          destruct (construct_viewc (csubst a k t)) eqn:eqc.
          2:{ f_equal. rewrite !map_map_compose. clear -etaa cla ev H0. solve_all. }
          simp isEtaExp in H2.
          rewrite /isEtaExp_app in H2.
          destruct lookup_constructor_pars_args as [[pars args]|] eqn:eqpars => // /=.
          rewrite (lookup_inductive_pars_constructor_pars_args eqpars).
          assert (pars = 0). rtoProp. eapply Nat.leb_le in H2. lia.
          subst pars. rewrite skipn_0.
          simp optimize; rewrite -optimize_equation_1.
          { f_equal. rewrite !map_map_compose. clear -etaa cla ev H0. solve_all. } }
    - pose proof (etaExp_csubst _ _ k _ etaa H0).
      rewrite !csubst_mkApps /= in H1 *.
      assert (map (csubst a k) v <> []).
      { destruct v; cbn; congruence. }
      rewrite optimize_mkApps //.
      rewrite isEtaExp_Constructor // in H1.
      move/andP: H1. rewrite map_length. move=> [] etaapp etav.
      cbn -[lookup_inductive_pars].
      unfold isEtaExp_app in etaapp.
      rewrite GlobalContextMap.lookup_inductive_pars_spec in Heq.
      rewrite Heq in etaapp *.
      f_equal.
      now destruct block_args; inv etav.
      rewrite map_skipn. f_equal.
      rewrite !map_map_compose.
      rewrite isEtaExp_Constructor // in H0. rtoProp. solve_all.
    - pose proof (etaExp_csubst _ _ k _ etaa H0).
      rewrite !csubst_mkApps /= in H1 *.
      assert (map (csubst a k) v <> []).
      { destruct v; cbn; congruence. }
      rewrite optimize_mkApps //.
      rewrite isEtaExp_Constructor // in H1.
      rewrite GlobalContextMap.lookup_inductive_pars_spec in Heq.
      move/andP: H1. rewrite map_length. move=> [] etaapp etav.
      cbn -[lookup_inductive_pars].
      unfold isEtaExp_app in etaapp.
      destruct lookup_constructor_pars_args as [[pars args]|] eqn:eqpars => //.
      now rewrite (lookup_inductive_pars_constructor_pars_args eqpars) in Heq.
  Qed.

  Lemma optimize_substl s t :
    forallb (closedn 0) s ->
    forallb (isEtaExp Σ) s ->
    isEtaExp Σ t ->
    optimize (substl s t) = substl (map optimize s) (optimize t).
  Proof using Type.
    induction s in t |- *; simpl; auto.
    move=> /andP[] cla cls /andP[] etaa etas etat.
    rewrite IHs //. now eapply etaExp_csubst. f_equal.
    now rewrite optimize_csubst.
  Qed.

  Lemma optimize_iota_red pars args br :
    forallb (closedn 0) args ->
    forallb (isEtaExp Σ) args ->
    isEtaExp Σ br.2 ->
    optimize (EGlobalEnv.iota_red pars args br) = EGlobalEnv.iota_red pars (map optimize args) (on_snd optimize br).
  Proof using Type.
    intros cl etaargs etabr.
    unfold EGlobalEnv.iota_red.
    rewrite optimize_substl //.
    rewrite forallb_rev forallb_skipn //.
    rewrite forallb_rev forallb_skipn //.
    now rewrite map_rev map_skipn.
  Qed.

  Lemma optimize_fix_subst mfix : EGlobalEnv.fix_subst (map (map_def optimize) mfix) = map optimize (EGlobalEnv.fix_subst mfix).
  Proof using Type.
    unfold EGlobalEnv.fix_subst.
    rewrite map_length.
    generalize #|mfix|.
    induction n; simpl; auto.
    f_equal; auto. now simp optimize.
  Qed.

  Lemma optimize_cofix_subst mfix : EGlobalEnv.cofix_subst (map (map_def optimize) mfix) = map optimize (EGlobalEnv.cofix_subst mfix).
  Proof using Type.
    unfold EGlobalEnv.cofix_subst.
    rewrite map_length.
    generalize #|mfix|.
    induction n; simpl; auto.
    f_equal; auto. now simp optimize.
  Qed.

  Lemma optimize_cunfold_fix mfix idx n f :
    forallb (closedn 0) (fix_subst mfix) ->
    forallb (fun d =>  isLambda (dbody d) && isEtaExp Σ (dbody d)) mfix ->
    cunfold_fix mfix idx = Some (n, f) ->
    cunfold_fix (map (map_def optimize) mfix) idx = Some (n, optimize f).
  Proof using Type.
    intros hfix heta.
    unfold cunfold_fix.
    rewrite nth_error_map.
    destruct nth_error eqn:heq.
    intros [= <- <-] => /=. f_equal. f_equal.
    rewrite optimize_substl //.
    now apply isEtaExp_fix_subst.
    solve_all. eapply nth_error_all in heta; tea. cbn in heta.
    rtoProp; intuition auto.
    f_equal. f_equal. apply optimize_fix_subst.
    discriminate.
  Qed.


  Lemma optimize_cunfold_cofix mfix idx n f :
    forallb (closedn 0) (cofix_subst mfix) ->
    forallb (isEtaExp Σ ∘ dbody) mfix ->
    cunfold_cofix mfix idx = Some (n, f) ->
    cunfold_cofix (map (map_def optimize) mfix) idx = Some (n, optimize f).
  Proof using Type.
    intros hcofix heta.
    unfold cunfold_cofix.
    rewrite nth_error_map.
    destruct nth_error eqn:heq.
    intros [= <- <-] => /=. f_equal.
    rewrite optimize_substl //.
    now apply isEtaExp_cofix_subst.
    solve_all. now eapply nth_error_all in heta; tea.
    f_equal. f_equal. apply optimize_cofix_subst.
    discriminate.
  Qed.

  Lemma optimize_nth {n l d} :
    optimize (nth n l d) = nth n (map optimize l) (optimize d).
  Proof using Type.
    induction l in n |- *; destruct n; simpl; auto.
  Qed.

End optimize.

#[universes(polymorphic)] Global Hint Rewrite @map_primIn_spec @map_InP_spec : optimize.
Tactic Notation "simp_eta" "in" hyp(H) := simp isEtaExp in H; rewrite -?isEtaExp_equation_1 in H.
Ltac simp_eta := simp isEtaExp; rewrite -?isEtaExp_equation_1.
Tactic Notation "simp_optimize" "in" hyp(H) := simp optimize in H; rewrite -?optimize_equation_1 in H.
Ltac simp_optimize := simp optimize; rewrite -?optimize_equation_1.

Definition optimize_constant_decl Σ cb :=
  {| cst_body := option_map (optimize Σ) cb.(cst_body) |}.

Definition optimize_inductive_decl idecl :=
  {| ind_finite := idecl.(ind_finite); ind_npars := 0; ind_bodies := idecl.(ind_bodies) |}.

Definition optimize_decl Σ d :=
  match d with
  | ConstantDecl cb => ConstantDecl (optimize_constant_decl Σ cb)
  | InductiveDecl idecl => InductiveDecl (optimize_inductive_decl idecl)
  end.

Definition optimize_env Σ :=
  map (on_snd (optimize_decl Σ)) Σ.(GlobalContextMap.global_decls).

Definition optimize_program (p : eprogram_env) : eprogram :=
  (ERemoveParams.optimize_env p.1, ERemoveParams.optimize p.1 p.2).

Import EGlobalEnv.

Lemma lookup_env_optimize Σ kn :
  lookup_env (optimize_env Σ) kn =
  option_map (optimize_decl Σ) (lookup_env Σ.(GlobalContextMap.global_decls) kn).
Proof.
  unfold optimize_env.
  destruct Σ as [Σ map repr wf]; cbn.
  induction Σ at 2 4; simpl; auto.
  case: eqb_spec => //.
Qed.

Lemma lookup_constructor_optimize {Σ kn c} :
  lookup_constructor (optimize_env Σ) kn c =
  match lookup_constructor Σ.(GlobalContextMap.global_decls) kn c with
  | Some (mdecl, idecl, cdecl) => Some (optimize_inductive_decl mdecl, idecl, cdecl)
  | None => None
  end.
Proof.
  rewrite /lookup_constructor /lookup_inductive /lookup_minductive.
  rewrite lookup_env_optimize.
  destruct lookup_env as [[]|] => /= //.
  do 2 destruct nth_error => //.
Qed.

Lemma lookup_constructor_pars_args_optimize (Σ : GlobalContextMap.t) i n npars nargs :
  EGlobalEnv.lookup_constructor_pars_args Σ i n = Some (npars, nargs) ->
  EGlobalEnv.lookup_constructor_pars_args (optimize_env Σ) i n = Some (0, nargs).
Proof.
  rewrite /EGlobalEnv.lookup_constructor_pars_args. rewrite lookup_constructor_optimize //=.
  destruct EGlobalEnv.lookup_constructor => //. destruct p as [[] ?] => //=. now intros [= <- <-].
Qed.

Lemma is_propositional_optimize (Σ : GlobalContextMap.t) ind :
  match inductive_isprop_and_pars Σ.(GlobalContextMap.global_decls) ind with
  | Some (prop, npars) =>
    inductive_isprop_and_pars (optimize_env Σ) ind = Some (prop, 0)
  | None =>
    inductive_isprop_and_pars (optimize_env Σ) ind = None
  end.
Proof.
  rewrite /inductive_isprop_and_pars /lookup_inductive /lookup_minductive.
  rewrite lookup_env_optimize.
  destruct lookup_env; simpl; auto.
  destruct g; simpl; auto. destruct nth_error => //.
Qed.

Lemma is_propositional_cstr_optimize {Σ : GlobalContextMap.t} {ind c} :
  match constructor_isprop_pars_decl Σ.(GlobalContextMap.global_decls) ind c with
  | Some (prop, npars, cdecl) =>
    constructor_isprop_pars_decl (optimize_env Σ) ind c = Some (prop, 0, cdecl)
  | None =>
  constructor_isprop_pars_decl (optimize_env Σ) ind c = None
  end.
Proof.
  rewrite /constructor_isprop_pars_decl /lookup_constructor /lookup_inductive /lookup_minductive.
  rewrite lookup_env_optimize.
  destruct lookup_env; simpl; auto.
  destruct g; simpl; auto. do 2 destruct nth_error => //.
Qed.

Lemma lookup_inductive_pars_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} ind :
  wf_glob Σ ->
  forall pars, lookup_inductive_pars Σ ind = Some pars ->
  EGlobalEnv.lookup_inductive_pars (optimize_env Σ) ind = Some 0.
Proof.
  rewrite /lookup_inductive_pars => wf pars.
  rewrite /lookup_inductive /lookup_minductive.
  rewrite (lookup_env_optimize _ ind).
  destruct lookup_env as [[decl|]|] => //=.
Qed.

Arguments eval {wfl}.

Arguments isEtaExp : simpl never.

Lemma isEtaExp_mkApps {Σ} {f u} : isEtaExp Σ (tApp f u) ->
  let (hd, args) := decompose_app (tApp f u) in
  match construct_viewc hd with
  | view_construct kn c block_args =>
    args <> [] /\ f = mkApps hd (remove_last args) /\ u = last args u /\
    isEtaExp_app Σ kn c #|args| && forallb (isEtaExp Σ) args && is_nil block_args
  | view_other _ discr =>
    [&& isEtaExp Σ hd, forallb (isEtaExp Σ) args, isEtaExp Σ f & isEtaExp Σ u]
  end.
Proof.
  move/(isEtaExp_mkApps Σ f [u]).
  cbn -[decompose_app]. destruct decompose_app eqn:da.
  destruct construct_viewc eqn:cv => //.
  intros ->.
  pose proof (decompose_app_inv da).
  pose proof (decompose_app_notApp _ _ _ da).
  destruct l using rev_case. cbn. intuition auto. solve_discr. noconf H.
  rewrite mkApps_app in H. noconf H.
  rewrite remove_last_app last_last. intuition auto.
  destruct l; cbn in *; congruence.
  pose proof (decompose_app_inv da).
  pose proof (decompose_app_notApp _ _ _ da).
  destruct l using rev_case. cbn. intuition auto. destruct t => //.
  rewrite mkApps_app in H. noconf H.
  move=> /andP[] etat. rewrite forallb_app => /andP[] etal /=.
  rewrite andb_true_r => etaa. rewrite etaa andb_true_r.
  rewrite etat etal. cbn. rewrite andb_true_r.
  eapply isEtaExp_mkApps_intro; auto; solve_all.
Qed.

Lemma decompose_app_tApp_split f a hd args :
  decompose_app (tApp f a) = (hd, args) -> f = mkApps hd (remove_last args) /\ a = last args a.
Proof.
  unfold decompose_app. cbn.
  move/decompose_app_rec_inv' => [n [napp [hskip heq]]].
  rewrite -(firstn_skipn n args).
  rewrite -hskip. rewrite last_last; split => //.
  rewrite heq. f_equal.
  now rewrite remove_last_app.
Qed.

Arguments lookup_inductive_pars_constructor_pars_args {Σ ind n pars args}.

Lemma optimize_tApp {Σ : GlobalContextMap.t} f a : isEtaExp Σ f -> isEtaExp Σ a -> optimize Σ (EAst.tApp f a) = EAst.tApp (optimize Σ f) (optimize Σ a).
Proof.
  move=> etaf etaa.
  pose proof (isEtaExp_mkApps_intro _ _ [a] etaf).
  forward H by eauto.
  move/isEtaExp_mkApps: H.
  destruct decompose_app eqn:da.
  destruct construct_viewc eqn:cv => //.
  { intros [? [? []]]. rewrite H0 /=.
    rewrite -[EAst.tApp _ _ ](mkApps_app _ _ [a]).
    move/andP: H2 => []. rewrite /isEtaExp_app.
    rewrite !optimize_mkApps // cv.
    destruct lookup_constructor_pars_args as [[pars args]|] eqn:hl => //.
    rewrite (lookup_inductive_pars_constructor_pars_args hl).
    intros hpars etal.
    rewrite -[EAst.tApp _ _ ](mkApps_app _ _ [optimize Σ a]).
    f_equal. rewrite !skipn_map !skipn_app map_app. f_equal.
    assert (pars - #|remove_last l| = 0) as ->.
    2:{ rewrite skipn_0 //. }
    rewrite H0 in etaf.
    rewrite isEtaExp_mkApps_napp // in etaf.
    simp construct_viewc in etaf.
    move/andP: etaf => []. rewrite /isEtaExp_app hl.
    move => /andP[] /Nat.leb_le. lia. }
  { move/and4P=> [] iset isel _ _. rewrite (decompose_app_inv da).
    pose proof (decompose_app_notApp _ _ _ da).
    rewrite optimize_mkApps //.
    destruct (decompose_app_tApp_split _ _ _ _ da).
    rewrite cv. rewrite H0.
    rewrite optimize_mkApps // cv.
    rewrite -[EAst.tApp _ _ ](mkApps_app _ _ [optimize Σ a]). f_equal.
    rewrite -[(_ ++ _)%list](map_app (optimize Σ) _ [a]).
    f_equal.
    assert (l <> []).
    { destruct l; try congruence. eapply decompose_app_inv in da. cbn in *. now subst t. }
    rewrite H1.
    now apply remove_last_last. }
Qed.

Module Fast.
  Section fastoptimize.
    Context (Σ : GlobalContextMap.t).

    Equations optimize (app : list term) (t : term) : term := {
    | app, tEvar ev args => mkApps (EAst.tEvar ev (optimize_args args)) app
    | app, tLambda na M => mkApps (EAst.tLambda na (optimize [] M)) app
    | app, tApp u v => optimize (optimize [] v :: app) u
    | app, tLetIn na b b' => mkApps (EAst.tLetIn na (optimize [] b) (optimize [] b')) app
    | app, tCase ind c brs =>
        let brs' := optimize_brs brs in
        mkApps (EAst.tCase (ind.1, 0) (optimize [] c) brs') app
    | app, tProj p c => mkApps (EAst.tProj {| proj_ind := p.(proj_ind); proj_npars := 0; proj_arg := p.(proj_arg) |} (optimize [] c)) app
    | app, tFix mfix idx =>
        let mfix' := optimize_defs mfix in
        mkApps (EAst.tFix mfix' idx) app
    | app, tCoFix mfix idx =>
        let mfix' := optimize_defs mfix in
        mkApps (EAst.tCoFix mfix' idx) app
    | app, tConstruct kn c block_args with GlobalContextMap.lookup_inductive_pars Σ (inductive_mind kn) := {
        | Some npars => mkApps (EAst.tConstruct kn c block_args) (List.skipn npars app)
        | None => mkApps (EAst.tConstruct kn c block_args) app }
    | app, tPrim (primInt; primIntModel i) => mkApps (tPrim (primInt; primIntModel i)) app
    | app, tPrim (primFloat; primFloatModel f) => mkApps (tPrim (primFloat; primFloatModel f)) app
    | app, tPrim (primArray; primArrayModel a) =>
      mkApps (tPrim (primArray; primArrayModel {| array_default := optimize [] a.(array_default); array_value := optimize_args a.(array_value) |})) app
    | app, x => mkApps x app }

    where optimize_args (t : list term) : list term :=
    { | [] := []
      | a :: args := (optimize [] a) :: optimize_args args
    }

    where optimize_brs (t : list (list BasicAst.name × term)) : list (list BasicAst.name × term) :=
    { | [] := []
      | a :: args := (a.1, (optimize [] a.2)) :: optimize_brs args }

    where optimize_defs (t : mfixpoint term) : mfixpoint term :=
    { | [] := []
      | d :: defs := {| dname := dname d; dbody := optimize [] d.(dbody); rarg := d.(rarg) |} :: optimize_defs defs
    }.

    Local Ltac specIH :=
          match goal with
          | [ H : (forall args : list term, _) |- _ ] => specialize (H [] eq_refl)
          end.

    Lemma optimize_acc_opt t :
      forall args, ERemoveParams.optimize Σ (mkApps t args) = optimize (map (ERemoveParams.optimize Σ) args) t.
    Proof using Type.
      intros args.
      remember (map (ERemoveParams.optimize Σ) args) as args'.
      revert args Heqargs'.
      set (P:= fun args' t fs => forall args, args' = map (ERemoveParams.optimize Σ) args -> ERemoveParams.optimize Σ (mkApps t args) = fs).
      apply (optimize_elim P
        (fun l l' => map (ERemoveParams.optimize Σ) l = l')
        (fun l l' => map (on_snd (ERemoveParams.optimize Σ)) l = l')
        (fun l l' => map (map_def (ERemoveParams.optimize Σ)) l = l')); subst P; cbn -[GlobalContextMap.lookup_inductive_pars isEtaExp ERemoveParams.optimize]; clear.
      all: try reflexivity.
      all: intros *; simp_eta; simp_optimize.
      all: try solve [intros; subst; rtoProp; rewrite optimize_mkApps // /=; simp_optimize; repeat specIH; repeat (f_equal; intuition eauto)].
      all: try solve [rewrite optimize_mkApps //].
      - intros IHv IHu.
        specialize (IHv [] eq_refl). simpl in IHv.
        intros args ->. specialize (IHu (v :: args)).
        forward IHu. now rewrite -IHv. exact IHu.
      - intros Hl hargs args ->.
        rewrite optimize_mkApps //=. simp_optimize.
        f_equal. f_equal. cbn.
        do 2 f_equal. rewrite /map_array_model.
        specialize (Hl [] eq_refl). f_equal; eauto.
      - intros Hl args ->.
        rewrite optimize_mkApps // /=.
        rewrite GlobalContextMap.lookup_inductive_pars_spec in Hl. now rewrite Hl.
      - intros Hl args ->.
        rewrite GlobalContextMap.lookup_inductive_pars_spec in Hl.
        now rewrite optimize_mkApps // /= Hl.
      - intros IHa heq.
        specIH. now rewrite IHa.
      - intros IHa heq; specIH. f_equal; eauto. unfold on_snd. now rewrite IHa.
      - intros IHa heq; specIH. unfold map_def. f_equal; eauto. now rewrite IHa.
    Qed.

    Lemma optimize_fast t : ERemoveParams.optimize Σ t = optimize [] t.
    Proof using Type. now apply (optimize_acc_opt t []). Qed.

  End fastoptimize.

  Notation optimize' Σ := (optimize Σ []).

  Definition optimize_constant_decl Σ cb :=
    {| cst_body := option_map (optimize' Σ) cb.(cst_body) |}.

  Definition optimize_inductive_decl idecl :=
    {| ind_finite := idecl.(ind_finite); ind_npars := 0; ind_bodies := idecl.(ind_bodies) |}.

  Definition optimize_decl Σ d :=
    match d with
    | ConstantDecl cb => ConstantDecl (optimize_constant_decl Σ cb)
    | InductiveDecl idecl => InductiveDecl (optimize_inductive_decl idecl)
    end.

  Definition optimize_env Σ :=
    map (on_snd (optimize_decl Σ)) Σ.(GlobalContextMap.global_decls).

  Lemma optimize_env_fast Σ : ERemoveParams.optimize_env Σ = optimize_env Σ.
  Proof.
    unfold ERemoveParams.optimize_env, optimize_env.
    destruct Σ as [Σ map repr wf]. cbn.
    induction Σ at 2 4; cbn; auto.
    f_equal; eauto.
    destruct a as [kn []]; cbn; auto.
    destruct c as [[b|]]; cbn; auto. unfold on_snd; cbn.
    do 2 f_equal. unfold ERemoveParams.optimize_constant_decl, optimize_constant_decl.
    simpl. f_equal. f_equal. apply optimize_fast.
  Qed.

End Fast.

Lemma isLambda_mkApps' f l :
  l <> nil ->
  ~~ EAst.isLambda (EAst.mkApps f l).
Proof.
  induction l using rev_ind; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma isBox_mkApps' f l :
  l <> nil ->
  ~~ isBox (EAst.mkApps f l).
Proof.
  induction l using rev_ind; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma isFix_mkApps' f l :
  l <> nil ->
  ~~ isFix (EAst.mkApps f l).
Proof.
  induction l using rev_ind; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma isLambda_mkApps_Construct ind n block_args l :
  ~~ EAst.isLambda (EAst.mkApps (EAst.tConstruct ind n block_args) l).
Proof.
  induction l using rev_ind; cbn; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma isBox_mkApps_Construct ind n block_args l :
  ~~ isBox (EAst.mkApps (EAst.tConstruct ind n block_args) l).
Proof.
  induction l using rev_ind; cbn; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma isFix_mkApps_Construct ind n block_args l :
  ~~ isFix (EAst.mkApps (EAst.tConstruct ind n block_args) l).
Proof.
  induction l using rev_ind; cbn; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma optimize_isLambda Σ f :
  EAst.isLambda f = EAst.isLambda (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize]; (try simp_optimize) => //.
  rewrite (negbTE (isLambda_mkApps' _ _ _)) //.
  rewrite (negbTE (isLambda_mkApps' _ _ _)) //; try apply map_nil => //.
  all:rewrite !(negbTE (isLambda_mkApps_Construct _ _ _ _)) //.
Qed.

Lemma optimize_isBox Σ f :
  isBox f = isBox (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  rewrite (negbTE (isBox_mkApps' _ _ _)) //.
  rewrite (negbTE (isBox_mkApps' _ _ _)) //; try apply map_nil => //.
  all:rewrite !(negbTE (isBox_mkApps_Construct _ _ _ _)) //.
Qed.

Lemma isApp_mkApps u v : v <> nil -> isApp (mkApps u v).
Proof.
  destruct v using rev_case; try congruence.
  rewrite mkApps_app /= //.
Qed.

Lemma optimize_isApp Σ f :
  ~~ EAst.isApp f ->
  ~~ EAst.isApp (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  all:rewrite isApp_mkApps //.
Qed.

Lemma optimize_isFix Σ f :
  isFix f = isFix (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  rewrite (negbTE (isFix_mkApps' _ _ _)) //.
  rewrite (negbTE (isFix_mkApps' _ _ _)) //; try apply map_nil => //.
  all:rewrite !(negbTE (isFix_mkApps_Construct _ _ _ _)) //.
Qed.

Lemma optimize_isFixApp Σ f :
  isFixApp f = isFixApp (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  all:rewrite isFixApp_mkApps isFixApp_mkApps //.
Qed.

Lemma optimize_isConstructApp Σ f :
  isConstructApp f = isConstructApp (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  all:rewrite isConstructApp_mkApps isConstructApp_mkApps //.
Qed.

Lemma optimize_isPrimApp Σ f :
  isPrimApp f = isPrimApp (optimize Σ f).
Proof.
  funelim (optimize Σ f); cbn -[optimize] => //.
  all:rewrite map_InP_spec.
  all:rewrite !isPrimApp_mkApps //.
Qed.

Lemma lookup_inductive_pars_is_prop_and_pars {Σ ind b pars} :
  inductive_isprop_and_pars Σ ind = Some (b, pars) ->
  lookup_inductive_pars Σ (inductive_mind ind) = Some pars.
Proof.
  rewrite /inductive_isprop_and_pars /lookup_inductive_pars /lookup_inductive /lookup_minductive.
  destruct lookup_env => //.
  destruct g => /= //.
  destruct nth_error => //. congruence.
Qed.

Lemma constructor_isprop_pars_decl_lookup {Σ ind c b pars decl} :
  constructor_isprop_pars_decl Σ ind c = Some (b, pars, decl) ->
  lookup_inductive_pars Σ (inductive_mind ind) = Some pars.
Proof.
  rewrite /constructor_isprop_pars_decl /lookup_constructor /lookup_inductive_pars /lookup_inductive /lookup_minductive.
  destruct lookup_env => //.
  destruct g => /= //.
  destruct nth_error => //. destruct nth_error => //. congruence.
Qed.

Lemma constructor_isprop_pars_inductive_pars {Σ ind c b pars decl} :
  constructor_isprop_pars_decl Σ ind c = Some (b, pars, decl) ->
  inductive_isprop_and_pars Σ ind = Some (b, pars).
Proof.
  rewrite /constructor_isprop_pars_decl /inductive_isprop_and_pars /lookup_constructor.
  destruct lookup_inductive as [[mdecl idecl]|] => /= //.
  destruct nth_error => //. congruence.
Qed.

Lemma lookup_constructor_lookup_inductive_pars {Σ ind c mdecl idecl cdecl} :
  lookup_constructor Σ ind c = Some (mdecl, idecl, cdecl) ->
  lookup_inductive_pars Σ (inductive_mind ind) = Some mdecl.(ind_npars).
Proof.
  rewrite /lookup_constructor /lookup_inductive_pars /lookup_inductive /lookup_minductive.
  destruct lookup_env => //.
  destruct g => /= //.
  destruct nth_error => //. destruct nth_error => //. congruence.
Qed.

Lemma optimize_mkApps_etaexp {Σ : GlobalContextMap.t} fn args :
  isEtaExp Σ fn ->
  optimize Σ (EAst.mkApps fn args) = EAst.mkApps (optimize Σ fn) (map (optimize Σ) args).
Proof.
  destruct (decompose_app fn) eqn:da.
  rewrite (decompose_app_inv da).
  rewrite isEtaExp_mkApps_napp. now eapply decompose_app_notApp.
  destruct construct_viewc eqn:vc.
  + move=> /andP[] hl0 etal0.
    rewrite -mkApps_app.
    rewrite (optimize_mkApps Σ (tConstruct ind n block_args)) // /=.
    rewrite optimize_mkApps // /=.
    unfold isEtaExp_app in hl0.
    destruct lookup_constructor_pars_args as [[pars args']|] eqn:hl => //.
    rtoProp.
    eapply Nat.leb_le in H.
    rewrite (lookup_inductive_pars_constructor_pars_args hl).
    rewrite -mkApps_app. f_equal. rewrite map_app.
    rewrite skipn_app. len. assert (pars - #|l| = 0) by lia.
    now rewrite H1 skipn_0.
  + move=> /andP[] etat0 etal0.
    rewrite -mkApps_app !optimize_mkApps; try now eapply decompose_app_notApp.
    rewrite vc. rewrite -mkApps_app !map_app //.
Qed.

 #[export] Instance Qpreserves_closedn (efl := all_env_flags) Σ : closed_env Σ ->
  Qpreserves (fun n x => closedn n x) Σ.
Proof.
  intros clΣ.
  split.
  - red. move=> n t.
    destruct t; cbn; intuition auto; try solve [constructor; auto].
    eapply on_evar; solve_all.
    eapply on_letin; rtoProp; intuition auto.
    eapply on_app; rtoProp; intuition auto.
    eapply on_case; rtoProp; intuition auto. solve_all.
    eapply on_fix. solve_all. solve_all.
    eapply on_cofix; solve_all.
    eapply on_prim; solve_all.
  - red. intros kn decl.
    move/(lookup_env_closed clΣ).
    unfold closed_decl. destruct EAst.cst_body => //.
  - red. move=> hasapp n t args. rewrite closedn_mkApps.
    split; intros; rtoProp; intuition auto; solve_all.
  - red. move=> hascase n ci discr brs. simpl.
    intros; rtoProp; intuition auto; solve_all.
  - red. move=> hasproj n p discr. simpl.
    intros; rtoProp; intuition auto; solve_all.
  - red. move=> t args clt cll.
    eapply closed_substl. solve_all. now rewrite Nat.add_0_r.
  - red. move=> n mfix idx. cbn.
    intros; rtoProp; intuition auto; solve_all.
  - red. move=> n mfix idx. cbn.
    intros; rtoProp; intuition auto; solve_all.
Qed.

Lemma optimize_eval (efl := all_env_flags) {wfl:WcbvFlags} {wcon : with_constructor_as_block = false} {Σ : GlobalContextMap.t} t v :
  isEtaExp_env Σ ->
  closed_env Σ ->
  wf_glob Σ ->
  closedn 0 t ->
  isEtaExp Σ t ->
  eval Σ t v ->
  eval (optimize_env Σ) (optimize Σ t) (optimize Σ v).
Proof.
  intros etaΣ clΣ wfΣ.
  revert t v.
  unshelve eapply (eval_preserve_mkApps_ind wfl wcon Σ (fun x y => eval (optimize_env Σ) (optimize Σ x) (optimize Σ y))
    (fun n x => closedn n x) (Qpres := Qpreserves_closedn Σ clΣ)) => //.
  { intros. eapply eval_closed; tea. }
  all:intros; simpl in *.
  (* 1-15: try solve [econstructor; eauto]. *)
  all:repeat destruct_nary_times => //.
  - rewrite optimize_tApp //.
    econstructor; eauto.

  - rewrite optimize_tApp //. simp_optimize in e1.
    econstructor; eauto.
    rewrite optimize_csubst // in e. now simp_eta in i10.

  - simp_optimize.
    rewrite optimize_csubst // in e.
    econstructor; eauto.

  - simp_optimize.
    set (brs' := map _ brs). cbn -[optimize].
    cbn in H3.
    rewrite optimize_mkApps // /= in e0.
    apply constructor_isprop_pars_decl_lookup in H2 as H1'.
    rewrite H1' in e0.
    pose proof (@is_propositional_cstr_optimize Σ ind c).
    rewrite H2 in H1.
    econstructor; eauto.
    * rewrite nth_error_map H3 //.
    * len. cbn in H4, H5. rewrite skipn_length. lia.
    * cbn -[optimize]. rewrite skipn_0. len.
    * cbn -[optimize].
      have etaargs : forallb (isEtaExp Σ) args.
      { rewrite isEtaExp_Constructor in i6.
        now move/andP: i6 => [] /andP[]. }
      rewrite optimize_iota_red // in e.
      rewrite closedn_mkApps in i4. now move/andP: i4.
      cbn. now eapply nth_error_forallb in H; tea.

  - subst brs. cbn in H4.
    rewrite andb_true_r in H4.
    rewrite optimize_substl // in e.
    eapply All_forallb, All_repeat => //.
    eapply All_forallb, All_repeat => //.
    rewrite map_optimize_repeat_box in e.
    simp_optimize. set (brs' := map _ _).
    cbn -[optimize]. eapply eval_iota_sing => //.
    now move: (is_propositional_optimize Σ ind); rewrite H2.

  - rewrite optimize_tApp //.
    rewrite optimize_mkApps // /= in e1.
    simp_optimize in e1.
    eapply eval_fix; tea.
    * rewrite map_length.
      eapply optimize_cunfold_fix; tea.
      eapply closed_fix_subst. tea.
      move: i8; rewrite closedn_mkApps => /andP[] //.
      move: i10; rewrite isEtaExp_mkApps_napp // /= => /andP[] //. simp_eta.
    * move: e.
      rewrite -[tApp _ _](mkApps_app _ _ [av]).
      rewrite -[tApp _ _](mkApps_app _ _ [optimize _ av]).
      rewrite optimize_mkApps_etaexp // map_app //.

  - rewrite optimize_tApp //.
    rewrite optimize_tApp //.
    rewrite optimize_mkApps //. simpl.
    simp_optimize. set (mfix' := map _ _). simpl.
    rewrite optimize_mkApps // /= in e0. simp_optimize in e0.
    eapply eval_fix_value; tea.
    eapply optimize_cunfold_fix; eauto.
    eapply closed_fix_subst => //.
    { move: i4.
      rewrite closedn_mkApps. now move/andP => []. }
    { move: i6. rewrite isEtaExp_mkApps_napp // /= => /andP[] //. now simp isEtaExp. }
    now rewrite map_length.

  - rewrite optimize_tApp //. simp_optimize in e0.
    simp_optimize in e1.
    eapply eval_fix'; tea.
    eapply optimize_cunfold_fix; tea.
    { eapply closed_fix_subst => //. }
    { simp isEtaExp in i10. }
    rewrite optimize_tApp // in e.

  - simp_optimize.
    rewrite optimize_mkApps // /= in e0.
    simp_optimize in e.
    simp_optimize in e0.
    set (brs' := map _ _) in *; simpl.
    eapply eval_cofix_case; tea.
    eapply optimize_cunfold_cofix; tea => //.
    { eapply closed_cofix_subst; tea.
      move: i5; rewrite closedn_mkApps => /andP[] //. }
    { move: i7. rewrite isEtaExp_mkApps_napp // /= => /andP[] //. now simp isEtaExp. }
    rewrite optimize_mkApps_etaexp // in e.

  - destruct p as [[ind pars] arg].
    simp_optimize.
    simp_optimize in e.
    rewrite optimize_mkApps // /= in e0.
    simp_optimize in e0.
    rewrite optimize_mkApps_etaexp // in e.
    simp_optimize in e0.
    eapply eval_cofix_proj; tea.
    eapply optimize_cunfold_cofix; tea.
    { eapply closed_cofix_subst; tea.
      move: i4; rewrite closedn_mkApps => /andP[] //. }
    { move: i6. rewrite isEtaExp_mkApps_napp // /= => /andP[] //. now simp isEtaExp. }

  - econstructor. red in H |- *.
    rewrite lookup_env_optimize H //.
    now rewrite /optimize_constant_decl H0.
    exact e.

  - simp_optimize.
    rewrite optimize_mkApps // /= in e0.
    rewrite (constructor_isprop_pars_decl_lookup H2) in e0.
    eapply eval_proj; eauto.
    move: (@is_propositional_cstr_optimize Σ p.(proj_ind) 0). now rewrite H2. simpl.
    len. rewrite skipn_length. cbn in H3. lia.
    rewrite nth_error_skipn nth_error_map /= H4 //.

  - simp_optimize. eapply eval_proj_prop => //.
    move: (is_propositional_optimize Σ p.(proj_ind)); now rewrite H3.

  - rewrite !optimize_tApp //.
    eapply eval_app_cong; tea.
    move: H1. eapply contraNN.
    rewrite -optimize_isLambda -optimize_isConstructApp -optimize_isFixApp -optimize_isBox -optimize_isPrimApp //.
    rewrite -optimize_isFix //.

  - rewrite !optimize_mkApps // /=.
    rewrite (lookup_constructor_lookup_inductive_pars H).
    eapply eval_mkApps_Construct; tea.
    + rewrite lookup_constructor_optimize H //.
    + constructor. cbn [atom]. rewrite wcon lookup_constructor_optimize H //.
    + rewrite /cstr_arity /=.
      move: H0; rewrite /cstr_arity /=.
      rewrite skipn_length map_length => ->. lia.
    + cbn in H0. eapply All2_skipn, All2_map.
      eapply All2_impl; tea; cbn -[optimize].
      intros x y []; auto.

  - depelim X; simp optimize; repeat constructor.
    eapply All2_over_undep in a. eapply All2_Set_All2 in ev. eapply All2_All2_Set. solve_all. now destruct b.
    now destruct a0.

  - destruct t => //.
    all:constructor; eauto. simp optimize.
    cbn [atom optimize] in H |- *.
    rewrite lookup_constructor_optimize.
    destruct lookup_constructor eqn:hl => //. destruct p as [[] ?] => //.
Qed.

From MetaCoq.Erasure Require Import EEtaExpanded.

Lemma optimize_declared_constructor {Σ : GlobalContextMap.t} {k mdecl idecl cdecl} :
  declared_constructor Σ.(GlobalContextMap.global_decls)  k mdecl idecl cdecl ->
  declared_constructor (optimize_env Σ) k (optimize_inductive_decl mdecl) idecl cdecl.
Proof.
  intros [[] ?]; do 2 split => //.
  red in H; red.
  rewrite lookup_env_optimize H //.
Qed.

Lemma lookup_inductive_pars_spec {Σ} {mind} {mdecl} :
  declared_minductive Σ mind mdecl ->
  lookup_inductive_pars Σ mind = Some (ind_npars mdecl).
Proof.
  rewrite /declared_minductive /lookup_inductive_pars /lookup_minductive.
  now intros -> => /=.
Qed.

Definition switch_no_params (efl : EEnvFlags) :=
  {| has_axioms := has_axioms;
     has_cstr_params := false;
     term_switches := term_switches ;
     cstr_as_blocks := cstr_as_blocks
     |}.

(* Stripping preserves well-formedness directly, not caring about eta-expansion *)
Lemma optimize_wellformed {efl} {Σ : GlobalContextMap.t} n t :
  cstr_as_blocks = false ->
  has_tApp ->
  @wf_glob efl Σ ->
  @wellformed efl Σ n t ->
  @wellformed (switch_no_params efl) (optimize_env Σ) n (optimize Σ t).
Proof.
  intros cab hasapp wfΣ.
  revert n.
  funelim (optimize Σ t); try intros n.
  all:cbn -[optimize lookup_constructor lookup_inductive]; simp_optimize; intros.
  all:try solve[unfold wf_fix_gen in *; rtoProp; intuition auto; toAll; solve_all].
  - cbn -[optimize]; simp_optimize. intros; rtoProp; intuition auto.
    rewrite lookup_env_optimize. destruct lookup_env eqn:hl => // /=.
    destruct g => /= //. destruct (cst_body c) => //.
  - rewrite cab in H |- *. cbn -[optimize] in *.
    rewrite lookup_env_optimize. destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => //. destruct nth_error => //.
  - cbn -[optimize].
    rewrite lookup_env_optimize. cbn in H1. destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => //. rtoProp; intuition auto.
    simp_optimize. toAll; solve_all.
    toAll. solve_all.
  - cbn -[optimize] in H0 |- *.
    rewrite lookup_env_optimize. destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g. cbn in H0. now rtoProp.
    destruct nth_error => //. all:rtoProp; intuition auto.
    destruct EAst.ind_ctors => //.
    destruct nth_error => //.
    all: eapply H; auto.
  - unfold wf_fix_gen in *. rewrite map_length. rtoProp; intuition auto. toAll; solve_all.
    now rewrite -optimize_isLambda. toAll; solve_all.
  - primProp. rtoProp; intuition eauto; solve_all_k 6.
  - move:H1; rewrite !wellformed_mkApps //. rtoProp; intuition auto.
    toAll; solve_all. toAll; solve_all.
  - move:H0; rewrite !wellformed_mkApps //. rtoProp; intuition auto.
    move: H1. cbn. rewrite cab.
    rewrite lookup_env_optimize. destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => //. destruct nth_error => //.
    toAll; solve_all. eapply All_skipn. solve_all.
  - move:H0; rewrite !wellformed_mkApps //. rtoProp; intuition auto.
    move: H1. cbn. rewrite cab.
    rewrite lookup_env_optimize. destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => //. destruct nth_error => //.
    toAll; solve_all.
Qed.

Lemma optimize_wellformed_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} t :
  cstr_as_blocks = false ->
  wf_glob Σ ->
  forall n, wellformed Σ n t -> wellformed (optimize_env Σ) n t.
Proof.
  intros hcstrs wfΣ. induction t using EInduction.term_forall_list_ind; cbn => //.
  all:try solve [intros; unfold wf_fix in *; rtoProp; intuition eauto; solve_all].
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct (cst_body c) => //.
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=; intros; rtoProp; eauto.
    destruct g eqn:hg => /= //; intros; rtoProp; eauto.
    destruct cstr_as_blocks => //; repeat split; eauto.
    destruct nth_error => /= //.
    destruct nth_error => /= //.
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => /= //.
    intros; rtoProp; intuition auto; solve_all.
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //.
    rewrite andb_false_r => //.
    destruct nth_error => /= //.
    destruct EAst.ind_ctors => /= //.
    all:intros; rtoProp; intuition auto; solve_all.
    destruct nth_error => //.
Qed.

Lemma optimize_wellformed_decl_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} d :
  cstr_as_blocks = false ->
  wf_glob Σ ->
  wf_global_decl Σ d -> wf_global_decl (optimize_env Σ) d.
Proof.
  intros hcstrs wf; destruct d => /= //.
  destruct (cst_body c) => /= //.
  now eapply optimize_wellformed_irrel.
Qed.

Lemma optimize_decl_wf (efl := all_env_flags) {Σ : GlobalContextMap.t} :
  wf_glob Σ ->
  forall d, wf_global_decl Σ d ->
  wf_global_decl (efl := switch_no_params efl) (optimize_env Σ) (optimize_decl Σ d).
Proof.
  intros wf d.
  destruct d => /= //.
  destruct (cst_body c) => /= //.
  now apply (optimize_wellformed (Σ := Σ) 0 t).
Qed.

Lemma fresh_global_optimize_env {Σ : GlobalContextMap.t} kn :
  fresh_global kn Σ ->
  fresh_global kn (optimize_env Σ).
Proof.
  unfold fresh_global. cbn. unfold optimize_env.
  induction (GlobalContextMap.global_decls Σ); cbn; constructor; auto. cbn.
  now depelim H. depelim H. eauto.
Qed.

From MetaCoq.Erasure Require Import EProgram.

Program Fixpoint optimize_env' Σ : EnvMap.fresh_globals Σ -> global_context :=
  match Σ with
  | [] => fun _ => []
  | hd :: tl => fun HΣ =>
    let Σg := GlobalContextMap.make tl (fresh_globals_cons_inv HΣ) in
    on_snd (optimize_decl Σg) hd :: optimize_env' tl (fresh_globals_cons_inv HΣ)
  end.

Lemma lookup_minductive_declared_minductive Σ ind mdecl :
  lookup_minductive Σ ind = Some mdecl <-> declared_minductive Σ ind mdecl.
Proof.
  unfold declared_minductive, lookup_minductive.
  destruct lookup_env => /= //. destruct g => /= //; split => //; congruence.
Qed.

Lemma lookup_minductive_declared_inductive Σ ind mdecl idecl :
  lookup_inductive Σ ind = Some (mdecl, idecl) <-> declared_inductive Σ ind mdecl idecl.
Proof.
  unfold declared_inductive, lookup_inductive.
  rewrite <- lookup_minductive_declared_minductive.
  destruct lookup_minductive => /= //.
  destruct nth_error eqn:hnth => //.
  split. intros [=]. subst. split => //.
  intros [[=] hnth']. subst. congruence.
  split => //. intros [[=] hnth']. congruence.
  split => //. intros [[=] hnth'].
Qed.

Lemma extends_lookup_inductive_pars {efl : EEnvFlags} {Σ Σ'} :
  extends Σ Σ' -> wf_glob Σ' ->
  forall ind t, lookup_inductive_pars Σ ind = Some t ->
    lookup_inductive_pars Σ' ind = Some t.
Proof.
  intros ext wf ind t.
  rewrite /lookup_inductive_pars.
  destruct (lookup_minductive Σ ind) eqn:hl => /= //.
  intros [= <-].
  apply lookup_minductive_declared_minductive in hl.
  eapply EExtends.weakening_env_declared_minductive in hl; tea.
  apply lookup_minductive_declared_minductive in hl. now rewrite hl.
Qed.

Lemma optimize_extends {efl : EEnvFlags} {Σ Σ' : GlobalContextMap.t} :
  has_tApp ->
  extends Σ Σ' -> wf_glob Σ' ->
  forall n t, wellformed Σ n t -> optimize Σ t = optimize Σ' t.
Proof.
  intros hasapp hext hwf n t. revert n.
  funelim (optimize Σ t); intros ?n; simp_optimize  => /= //.
  all:try solve [intros; unfold wf_fix in *; rtoProp; intuition auto; f_equal; auto; toAll; solve_all].
  - intros; rtoProp; intuition auto.
    move: H1; rewrite wellformed_mkApps // => /andP[] wfu wfargs.
    rewrite optimize_mkApps // Heq /=. f_equal; eauto. toAll; solve_all.
  - rewrite wellformed_mkApps // => /andP[] wfc wfv.
    rewrite optimize_mkApps // /=.
    rewrite GlobalContextMap.lookup_inductive_pars_spec in Heq.
    eapply (extends_lookup_inductive_pars hext hwf) in Heq.
    rewrite Heq. f_equal. f_equal.
    toAll; solve_all.
  - rewrite wellformed_mkApps // => /andP[] wfc wfv.
    rewrite optimize_mkApps // /=.
    move: Heq.
    rewrite GlobalContextMap.lookup_inductive_pars_spec.
    unfold wellformed in wfc. move/andP: wfc => [] /andP[] hacc hc bargs.
    unfold lookup_inductive_pars. destruct lookup_minductive eqn:heq => //.
    unfold lookup_constructor, lookup_inductive in hc. rewrite heq /= // in hc.
Qed.

Lemma optimize_decl_extends {efl : EEnvFlags} {Σ Σ' : GlobalContextMap.t} :
  has_tApp ->
  extends Σ Σ' -> wf_glob Σ' ->
  forall d, wf_global_decl Σ d -> optimize_decl Σ d = optimize_decl Σ' d.
Proof.
  intros hast ext wf []; cbn.
  unfold optimize_constant_decl.
  destruct (EAst.cst_body c) eqn:hc => /= //.
  intros hwf. f_equal. f_equal. f_equal.
  eapply optimize_extends => //. exact hwf.
  intros _ => //.
Qed.

From MetaCoq.Erasure Require Import EGenericGlobalMap.

#[local]
Instance GT : GenTransform := { gen_transform := optimize; gen_transform_inductive_decl := optimize_inductive_decl }.
#[local]
Instance GTExt efl : has_tApp -> GenTransformExtends efl efl GT.
Proof.
  intros hasapp Σ t n wfΣ Σ' ext wf wf'.
  unfold gen_transform, GT.
  eapply optimize_extends; tea.
Qed.
#[local]
Instance GTWf efl : GenTransformWf efl (switch_no_params efl) GT.
Proof.
  refine {| gen_transform_pre := fun _ _ => has_tApp /\ cstr_as_blocks = false |}; auto.
  - unfold wf_minductive; intros []. cbn. repeat rtoProp. intuition auto.
  - intros Σ n t [? ?] wfΣ wft. unfold gen_transform_env, gen_transform. simpl.
    eapply optimize_wellformed => //.
Defined.

Lemma optimize_extends' {efl : EEnvFlags} {Σ Σ' : GlobalContextMap.t} :
  has_tApp ->
  extends Σ Σ' ->
  wf_glob Σ ->
  wf_glob Σ' ->
  List.map (on_snd (optimize_decl Σ)) Σ.(GlobalContextMap.global_decls) =
  List.map (on_snd (optimize_decl Σ')) Σ.(GlobalContextMap.global_decls).
Proof.
  intros hast ext wf.
  now apply (gen_transform_env_extends' (gt := GTExt efl hast) ext).
Qed.

Lemma optimize_extends_env {efl : EEnvFlags} {Σ Σ' : GlobalContextMap.t} :
  has_tApp ->
  extends Σ Σ' ->
  wf_glob Σ ->
  wf_glob Σ' ->
  extends (optimize_env Σ) (optimize_env Σ').
Proof.
  intros hast ext wf.
  now apply (gen_transform_extends (gt := GTExt efl hast) ext).
Qed.

Lemma optimize_env_eq (efl := all_env_flags) (Σ : GlobalContextMap.t) : wf_glob Σ -> optimize_env Σ = optimize_env' Σ.(GlobalContextMap.global_decls) Σ.(GlobalContextMap.wf).
Proof.
  intros wf.
  unfold optimize_env.
  destruct Σ; cbn. cbn in wf.
  induction global_decls in map, repr, wf0, wf |- * => //.
  cbn. f_equal.
  destruct a as [kn d]; unfold on_snd; cbn. f_equal. symmetry.
  eapply optimize_decl_extends => //. cbn. cbn. eapply EExtends.extends_prefix_extends. now exists [(kn, d)]. auto. cbn. now depelim wf.
  set (Σg' := GlobalContextMap.make global_decls (fresh_globals_cons_inv wf0)).
  erewrite <- (IHglobal_decls (GlobalContextMap.map Σg') (GlobalContextMap.repr Σg')).
  2:now depelim wf.
  set (Σg := {| GlobalContextMap.global_decls := _ :: _ |}).
  symmetry. eapply (optimize_extends' (Σ := Σg') (Σ' := Σg)) => //.
  cbn. eapply EExtends.extends_prefix_extends => //. now exists [a].
  cbn. now depelim wf.
Qed.

Lemma optimize_env_wf (efl := all_env_flags) {Σ : GlobalContextMap.t} :
  wf_glob Σ -> wf_glob (efl := switch_no_params efl) (optimize_env Σ).
Proof.
  intros wf.
  rewrite (optimize_env_eq _ wf).
  destruct Σ as [Σ map repr fr]; cbn in *.
  induction Σ in map, repr, fr, wf |- *.
  - cbn. constructor.
  - cbn.
    set (Σg := GlobalContextMap.make Σ (fresh_globals_cons_inv fr)).
    constructor; eauto.
    eapply (IHΣ (GlobalContextMap.map Σg) (GlobalContextMap.repr Σg)). now depelim wf.
    depelim wf. cbn.
    rewrite -(optimize_env_eq Σg). now cbn. cbn.
    now eapply (optimize_decl_wf (Σ:=Σg)).
    rewrite -(optimize_env_eq Σg). now depelim wf.
    eapply fresh_global_optimize_env. now depelim fr.
Qed.

Lemma optimize_program_wf (efl := all_env_flags) (p : eprogram_env) :
  wf_eprogram_env efl p ->
  wf_eprogram (switch_no_params efl) (optimize_program p).
Proof.
  intros []; split => //.
  eapply (optimize_env_wf H).
  now eapply optimize_wellformed.
Qed.

Lemma optimize_expanded {Σ : GlobalContextMap.t} {t} : expanded Σ t -> expanded (optimize_env Σ) (optimize Σ t).
Proof.
  induction 1 using expanded_ind.
  all:try solve[simp_optimize; constructor; eauto; solve_all].
  - rewrite optimize_mkApps_etaexp. now eapply expanded_isEtaExp.
    eapply expanded_mkApps_expanded => //. solve_all.
  - simp_optimize; constructor; eauto. solve_all.
    rewrite -optimize_isLambda //.
  - rewrite optimize_mkApps // /=.
    rewrite (lookup_inductive_pars_spec (proj1 (proj1 H))).
    eapply expanded_tConstruct_app.
    eapply optimize_declared_constructor; tea.
    len. rewrite skipn_length /= /EAst.cstr_arity /=.
    rewrite /EAst.cstr_arity in H0. lia.
    solve_all. eapply All_skipn. solve_all.
Qed.

Lemma optimize_expanded_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} t : wf_glob Σ -> expanded Σ t -> expanded (optimize_env Σ) t.
Proof.
  intros wf; induction 1 using expanded_ind.
  all:try solve[constructor; eauto; solve_all].
  eapply expanded_tConstruct_app.
  destruct H as [[H ?] ?].
  split => //. split => //. red.
  red in H. rewrite lookup_env_optimize // /= H //. 1-2:eauto.
  cbn. rewrite /EAst.cstr_arity in H0. lia. solve_all.
Qed.

Lemma optimize_expanded_decl {Σ : GlobalContextMap.t} t : expanded_decl Σ t -> expanded_decl (optimize_env Σ) (optimize_decl Σ t).
Proof.
  destruct t as [[[]]|] => /= //.
  unfold expanded_constant_decl => /=.
  apply optimize_expanded.
Qed.

Lemma optimize_env_expanded (efl := all_env_flags) {Σ : GlobalContextMap.t} :
  wf_glob Σ -> expanded_global_env Σ -> expanded_global_env (optimize_env Σ).
Proof.
  unfold expanded_global_env.
  intros wf. rewrite optimize_env_eq //.
  destruct Σ as [Σ map repr wf']; cbn in *.
  intros exp; induction exp in map, repr, wf', wf |- *; cbn.
  - constructor; auto.
  - set (Σ' := GlobalContextMap.make Σ (fresh_globals_cons_inv wf')).
    constructor; auto.
    eapply IHexp. eapply Σ'. now depelim wf. cbn.
    eapply (optimize_expanded_decl (Σ := Σ')) in H.
    rewrite -(optimize_env_eq Σ'). cbn. now depelim wf.
    exact H.
Qed.

Import EProgram.

Lemma optimize_program_expanded (efl := all_env_flags) (p : eprogram_env) :
  wf_eprogram_env efl p ->
  expanded_eprogram_env_cstrs p ->
  expanded_eprogram_cstrs (optimize_program p).
Proof.
  unfold expanded_eprogram_env_cstrs, expanded_eprogram_cstrs.
  move=> [] wfe wft. move/andP => [] etaenv etap.
  apply/andP; split.
  eapply expanded_global_env_isEtaExp_env, optimize_env_expanded => //.
  now eapply isEtaExp_env_expanded_global_env.
  now eapply expanded_isEtaExp, optimize_expanded, isEtaExp_expanded.
Qed.


        tConstruct ind n (map optimize args)
    | tPrim p => tPrim (map_prim optimize p)
    end.

  Lemma optimize_mkApps f l : optimize (mkApps f l) = mkApps (optimize f) (map optimize l).
  Proof using Type.
    induction l using rev_ind; simpl; auto.
    now rewrite mkApps_app /= IHl map_app /= mkApps_app /=.
  Qed.

  Lemma map_optimize_repeat_box n : map optimize (repeat tBox n) = repeat tBox n.
  Proof using Type. by rewrite map_repeat. Qed.

  (* move to globalenv *)

  Lemma isLambda_optimize t : isLambda t -> isLambda (optimize t).
  Proof. destruct t => //. Qed.
  Lemma isBox_optimize t : isBox t -> isBox (optimize t).
  Proof. destruct t => //. Qed.

  Lemma wf_optimize t k :
    wf_glob Σ ->
    wellformed Σ k t -> wellformed Σ k (optimize t).
  Proof using Type.
    intros wfΣ.
    induction t in k |- * using EInduction.term_forall_list_ind; simpl; auto;
    intros; try easy;
    rewrite -> ?map_map_compose, ?compose_on_snd, ?compose_map_def, ?map_length;
    unfold wf_fix_gen, test_def in *;
    simpl closed in *; try solve [simpl subst; simpl closed; f_equal; auto; rtoProp; solve_all]; try easy.
    - rtoProp. split; eauto. destruct args; eauto.
    - move/andP: H => [] /andP[] -> clt cll /=.
      rewrite IHt //=. solve_all.
    - rewrite GlobalContextMap.lookup_projection_spec.
      destruct lookup_projection as [[[[mdecl idecl] cdecl] pdecl]|] eqn:hl; auto => //.
      simpl.
      have arglen := wellformed_projection_args wfΣ hl.
      apply lookup_projection_lookup_constructor, lookup_constructor_lookup_inductive in hl.
      rewrite hl /= andb_true_r.
      rewrite IHt //=; len. apply Nat.ltb_lt.
      lia.
    - len. rtoProp; solve_all. solve_all.
      now eapply isLambda_optimize. solve_all.
    - len. rtoProp; repeat solve_all.
    - rewrite test_prim_map. rtoProp; intuition eauto; solve_all.
  Qed.

  Lemma optimize_csubst {a k b} n :
    wf_glob Σ ->
    wellformed Σ (k + n) b ->
    optimize (ECSubst.csubst a k b) = ECSubst.csubst (optimize a) k (optimize b).
  Proof using Type.
    intros wfΣ.
    induction b in k |- * using EInduction.term_forall_list_ind; simpl; auto;
    intros wft; try easy;
    rewrite -> ?map_map_compose, ?compose_on_snd, ?compose_map_def, ?map_length;
    unfold wf_fix, test_def in *;
    simpl closed in *; try solve [simpl subst; simpl closed; f_equal; auto; rtoProp; solve_all]; try easy.
    - destruct (k ?= n0)%nat; auto.
    - f_equal. rtoProp. now destruct args; inv H0.
    - move/andP: wft => [] /andP[] hi hb hl. rewrite IHb. f_equal. unfold on_snd; solve_all.
      repeat toAll. f_equal. solve_all. unfold on_snd; cbn. f_equal.
      rewrite a0 //. now rewrite -Nat.add_assoc.
    - move/andP: wft => [] hp hb.
      rewrite GlobalContextMap.lookup_projection_spec.
      destruct lookup_projection as [[[[mdecl idecl] cdecl] pdecl]|] eqn:hl => /= //.
      f_equal; eauto. f_equal. len. f_equal.
      have arglen := wellformed_projection_args wfΣ hl.
      case: Nat.compare_spec. lia. lia.
      auto.
    - f_equal. move/andP: wft => [hlam /andP[] hidx hb].
      solve_all. unfold map_def. f_equal.
      eapply a0. now rewrite -Nat.add_assoc.
    - f_equal. move/andP: wft => [hidx hb].
      solve_all. unfold map_def. f_equal.
      eapply a0. now rewrite -Nat.add_assoc.
  Qed.

  Lemma optimize_substl s t :
    wf_glob Σ ->
    forallb (wellformed Σ 0) s ->
    wellformed Σ #|s| t ->
    optimize (substl s t) = substl (map optimize s) (optimize t).
  Proof using Type.
    intros wfΣ. induction s in t |- *; simpl; auto.
    move/andP => [] cla cls wft.
    rewrite IHs //. eapply wellformed_csubst => //.
    f_equal. rewrite (optimize_csubst (S #|s|)) //.
  Qed.

  Lemma optimize_iota_red pars args br :
    wf_glob Σ ->
    forallb (wellformed Σ 0) args ->
    wellformed Σ #|skipn pars args| br.2 ->
    optimize (EGlobalEnv.iota_red pars args br) = EGlobalEnv.iota_red pars (map optimize args) (on_snd optimize br).
  Proof using Type.
    intros wfΣ wfa wfbr.
    unfold EGlobalEnv.iota_red.
    rewrite optimize_substl //.
    rewrite forallb_rev forallb_skipn //.
    now rewrite List.rev_length.
    now rewrite map_rev map_skipn.
  Qed.

  Lemma optimize_fix_subst mfix : EGlobalEnv.fix_subst (map (map_def optimize) mfix) = map optimize (EGlobalEnv.fix_subst mfix).
  Proof using Type.
    unfold EGlobalEnv.fix_subst.
    rewrite map_length.
    generalize #|mfix|.
    induction n; simpl; auto.
    f_equal; auto.
  Qed.

  Lemma optimize_cofix_subst mfix : EGlobalEnv.cofix_subst (map (map_def optimize) mfix) = map optimize (EGlobalEnv.cofix_subst mfix).
  Proof using Type.
    unfold EGlobalEnv.cofix_subst.
    rewrite map_length.
    generalize #|mfix|.
    induction n; simpl; auto.
    f_equal; auto.
  Qed.

  Lemma optimize_cunfold_fix mfix idx n f :
    wf_glob Σ ->
    wellformed Σ 0 (tFix mfix idx) ->
    cunfold_fix mfix idx = Some (n, f) ->
    cunfold_fix (map (map_def optimize) mfix) idx = Some (n, optimize f).
  Proof using Type.
    intros wfΣ hfix.
    unfold cunfold_fix.
    rewrite nth_error_map.
    cbn in hfix. move/andP: hfix => [] hlam /andP[] hidx hfix.
    destruct nth_error eqn:hnth => //.
    intros [= <- <-] => /=. f_equal.
    rewrite optimize_substl //. eapply wellformed_fix_subst => //.
    rewrite fix_subst_length.
    eapply nth_error_forallb in hfix; tea. now rewrite Nat.add_0_r in hfix.
    now rewrite optimize_fix_subst.
  Qed.

  Lemma optimize_cunfold_cofix mfix idx n f :
    wf_glob Σ ->
    wellformed Σ 0 (tCoFix mfix idx) ->
    cunfold_cofix mfix idx = Some (n, f) ->
    cunfold_cofix (map (map_def optimize) mfix) idx = Some (n, optimize f).
  Proof using Type.
    intros wfΣ hfix.
    unfold cunfold_cofix.
    rewrite nth_error_map.
    cbn in hfix. move/andP: hfix => [] hidx hfix.
    destruct nth_error eqn:hnth => //.
    intros [= <- <-] => /=. f_equal.
    rewrite optimize_substl //. eapply wellformed_cofix_subst => //.
    rewrite cofix_subst_length.
    eapply nth_error_forallb in hfix; tea. now rewrite Nat.add_0_r in hfix.
    now rewrite optimize_cofix_subst.
  Qed.

End optimize.

Definition optimize_constant_decl Σ cb :=
  {| cst_body := option_map (optimize Σ) cb.(cst_body) |}.

Definition optimize_decl Σ d :=
  match d with
  | ConstantDecl cb => ConstantDecl (optimize_constant_decl Σ cb)
  | InductiveDecl idecl => InductiveDecl idecl
  end.

Definition optimize_env Σ :=
  map (on_snd (optimize_decl Σ)) Σ.(GlobalContextMap.global_decls).

Import EnvMap.

Program Fixpoint optimize_env' Σ : EnvMap.fresh_globals Σ -> global_context :=
  match Σ with
  | [] => fun _ => []
  | hd :: tl => fun HΣ =>
    let Σg := GlobalContextMap.make tl (fresh_globals_cons_inv HΣ) in
    on_snd (optimize_decl Σg) hd :: optimize_env' tl (fresh_globals_cons_inv HΣ)
  end.

Import EGlobalEnv EExtends.

Lemma extends_lookup_projection {efl : EEnvFlags} {Σ Σ' p} : extends Σ Σ' -> wf_glob Σ' ->
  isSome (lookup_projection Σ p) ->
  lookup_projection Σ p = lookup_projection Σ' p.
Proof.
  intros ext wf; cbn.
  unfold lookup_projection.
  destruct lookup_constructor as [[[mdecl idecl] cdecl]|] eqn:hl => //.
  simpl.
  rewrite (extends_lookup_constructor wf ext _ _ _ hl) //.
Qed.

Lemma wellformed_optimize_extends {wfl: EEnvFlags} {Σ : GlobalContextMap.t} t :
  forall n, EWellformed.wellformed Σ n t ->
  forall {Σ' : GlobalContextMap.t}, extends Σ Σ' -> wf_glob Σ' ->
  optimize Σ t = optimize Σ' t.
Proof.
  induction t using EInduction.term_forall_list_ind; cbn -[lookup_constant lookup_inductive
    GlobalContextMap.lookup_projection]; intros => //.
  all:unfold wf_fix_gen in *; rtoProp; intuition auto.
  5:{ destruct cstr_as_blocks; rtoProp. f_equal; eauto; solve_all. destruct args; cbn in *; eauto. }
  all:f_equal; eauto; solve_all.
  - rewrite !GlobalContextMap.lookup_projection_spec.
    rewrite -(extends_lookup_projection H0 H1 H3).
    destruct lookup_projection as [[[[]]]|]. f_equal; eauto.
    now cbn in H3.
Qed.

Lemma wellformed_optimize_decl_extends {wfl: EEnvFlags} {Σ : GlobalContextMap.t} t :
  wf_global_decl Σ t ->
  forall {Σ' : GlobalContextMap.t}, extends Σ Σ' -> wf_glob Σ' ->
  optimize_decl Σ t = optimize_decl Σ' t.
Proof.
  destruct t => /= //.
  intros wf Σ' ext wf'. f_equal. unfold optimize_constant_decl. f_equal.
  destruct (cst_body c) => /= //. f_equal.
  now eapply wellformed_optimize_extends.
Qed.

Lemma lookup_env_optimize_env_Some {efl : EEnvFlags} {Σ : GlobalContextMap.t} kn d :
  wf_glob Σ ->
  GlobalContextMap.lookup_env Σ kn = Some d ->
  ∑ Σ' : GlobalContextMap.t,
    [× extends_prefix Σ' Σ, wf_global_decl Σ' d &
      lookup_env (optimize_env Σ) kn = Some (optimize_decl Σ' d)].
Proof.
  rewrite GlobalContextMap.lookup_env_spec.
  destruct Σ as [Σ map repr wf].
  induction Σ in map, repr, wf |- *; simpl; auto => //.
  intros wfg.
  case: eqb_specT => //.
  - intros ->. cbn. intros [= <-].
    exists (GlobalContextMap.make Σ (fresh_globals_cons_inv wf)). split.
    now eexists [_].
    cbn. now depelim wfg.
    f_equal. symmetry. eapply wellformed_optimize_decl_extends. cbn. now depelim wfg.
    eapply extends_prefix_extends.
    cbn. now exists [a]. now cbn. now cbn.
  - intros _.
    set (Σ' := GlobalContextMap.make Σ (fresh_globals_cons_inv wf)).
    specialize (IHΣ (GlobalContextMap.map Σ') (GlobalContextMap.repr Σ') (GlobalContextMap.wf Σ')).
    cbn in IHΣ. forward IHΣ. now depelim wfg.
    intros hl. specialize (IHΣ hl) as [Σ'' [ext wfgd hl']].
    exists Σ''. split => //.
    * destruct ext as [? ->].
      now exists (a :: x).
    * rewrite -hl'. f_equal.
      clear -wfg.
      eapply map_ext_in => kn hin. unfold on_snd. f_equal.
      symmetry. eapply wellformed_optimize_decl_extends => //. cbn.
      eapply lookup_env_In in hin. 2:now depelim wfg.
      depelim wfg. eapply lookup_env_wellformed; tea.
      eapply extends_prefix_extends.
      cbn. now exists [a]. now cbn.
Qed.

Lemma lookup_env_map_snd Σ f kn : lookup_env (List.map (on_snd f) Σ) kn = option_map f (lookup_env Σ kn).
Proof.
  induction Σ; cbn; auto.
  case: eqb_spec => //.
Qed.

Lemma lookup_env_optimize_env_None {efl : EEnvFlags} {Σ : GlobalContextMap.t} kn :
  GlobalContextMap.lookup_env Σ kn = None ->
  lookup_env (optimize_env Σ) kn = None.
Proof.
  rewrite GlobalContextMap.lookup_env_spec.
  destruct Σ as [Σ map repr wf].
  cbn. intros hl. rewrite lookup_env_map_snd hl //.
Qed.

Lemma lookup_env_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} kn :
  wf_glob Σ ->
  lookup_env (optimize_env Σ) kn = option_map (optimize_decl Σ) (lookup_env Σ kn).
Proof.
  intros wf.
  rewrite -GlobalContextMap.lookup_env_spec.
  destruct (GlobalContextMap.lookup_env Σ kn) eqn:hl.
  - eapply lookup_env_optimize_env_Some in hl as [Σ' [ext wf' hl']] => /=.
    rewrite hl'. f_equal.
    eapply wellformed_optimize_decl_extends; eauto.
    now eapply extends_prefix_extends. auto.

  - cbn. now eapply lookup_env_optimize_env_None in hl.
Qed.

Lemma is_propositional_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} ind :
  wf_glob Σ ->
  inductive_isprop_and_pars Σ ind = inductive_isprop_and_pars (optimize_env Σ) ind.
Proof.
  rewrite /inductive_isprop_and_pars => wf.
  rewrite /lookup_inductive /lookup_minductive.
  rewrite (lookup_env_optimize (inductive_mind ind) wf).
  rewrite /GlobalContextMap.inductive_isprop_and_pars /GlobalContextMap.lookup_inductive
    /GlobalContextMap.lookup_minductive.
  destruct lookup_env as [[decl|]|] => //.
Qed.

Lemma lookup_inductive_pars_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} ind :
  wf_glob Σ ->
  EGlobalEnv.lookup_inductive_pars Σ ind = EGlobalEnv.lookup_inductive_pars (optimize_env Σ) ind.
Proof.
  rewrite /lookup_inductive_pars => wf.
  rewrite /lookup_inductive /lookup_minductive.
  rewrite (lookup_env_optimize ind wf).
  rewrite /GlobalContextMap.lookup_inductive /GlobalContextMap.lookup_minductive.
  destruct lookup_env as [[decl|]|] => //.
Qed.

Lemma is_propositional_cstr_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} ind c :
  wf_glob Σ ->
  constructor_isprop_pars_decl Σ ind c = constructor_isprop_pars_decl (optimize_env Σ) ind c.
Proof.
  rewrite /constructor_isprop_pars_decl => wf.
  rewrite /lookup_constructor /lookup_inductive /lookup_minductive.
  rewrite (lookup_env_optimize (inductive_mind ind) wf).
  rewrite /GlobalContextMap.inductive_isprop_and_pars /GlobalContextMap.lookup_inductive
    /GlobalContextMap.lookup_minductive.
  destruct lookup_env as [[decl|]|] => //.
Qed.


Lemma closed_iota_red pars c args brs br :
  forallb (closedn 0) args ->
  nth_error brs c = Some br ->
  #|skipn pars args| = #|br.1| ->
  closedn #|br.1| br.2 ->
  closed (iota_red pars args br).
Proof.
  intros clargs hnth hskip clbr.
  rewrite /iota_red.
  eapply ECSubst.closed_substl => //.
  now rewrite forallb_rev forallb_skipn.
  now rewrite List.rev_length hskip Nat.add_0_r.
Qed.

Definition disable_prop_cases fl := {| with_prop_case := false; with_guarded_fix := fl.(@with_guarded_fix) ; with_constructor_as_block := false |}.

Lemma isFix_mkApps t l : isFix (mkApps t l) = isFix t && match l with [] => true | _ => false end.
Proof.
  induction l using rev_ind; cbn.
  - now rewrite andb_true_r.
  - rewrite mkApps_app /=. now destruct l => /= //; rewrite andb_false_r.
Qed.

Lemma lookup_constructor_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} {ind c} :
  wf_glob Σ ->
  lookup_constructor Σ ind c = lookup_constructor (optimize_env Σ) ind c.
Proof.
  intros wfΣ. rewrite /lookup_constructor /lookup_inductive /lookup_minductive.
  rewrite lookup_env_optimize // /=. destruct lookup_env => // /=.
  destruct g => //.
Qed.

Lemma lookup_projection_optimize {efl : EEnvFlags} {Σ : GlobalContextMap.t} {p} :
  wf_glob Σ ->
  lookup_projection Σ p = lookup_projection (optimize_env Σ) p.
Proof.
  intros wfΣ. rewrite /lookup_projection.
  rewrite -lookup_constructor_optimize //.
Qed.

Lemma constructor_isprop_pars_decl_inductive {Σ ind c} {prop pars cdecl} :
  constructor_isprop_pars_decl Σ ind c = Some (prop, pars, cdecl)  ->
  inductive_isprop_and_pars Σ ind = Some (prop, pars).
Proof.
  rewrite /constructor_isprop_pars_decl /inductive_isprop_and_pars /lookup_constructor.
  destruct lookup_inductive as [[mdecl idecl]|]=> /= //.
  destruct nth_error => //. congruence.
Qed.

Lemma constructor_isprop_pars_decl_constructor {Σ ind c} {mdecl idecl cdecl} :
  lookup_constructor Σ ind c = Some (mdecl, idecl, cdecl) ->
  constructor_isprop_pars_decl Σ ind c = Some (ind_propositional idecl, ind_npars mdecl, cdecl).
Proof.
  rewrite /constructor_isprop_pars_decl. intros -> => /= //.
Qed.

Lemma wf_mkApps Σ k f args : reflect (wellformed Σ k f /\ forallb (wellformed Σ k) args) (wellformed Σ k (mkApps f args)).
Proof.
  rewrite wellformed_mkApps //. eapply andP.
Qed.

Lemma substl_closed s t : closed t -> substl s t = t.
Proof.
  induction s in t |- *; cbn => //.
  intros clt. rewrite csubst_closed //. now apply IHs.
Qed.

Lemma substl_rel s k a :
  closed a ->
  nth_error s k = Some a ->
  substl s (tRel k) = a.
Proof.
  intros cla.
  induction s in k |- *.
  - rewrite nth_error_nil //.
  - destruct k => //=.
    * intros [= ->]. rewrite substl_closed //.
    * intros hnth. now apply IHs.
Qed.


Lemma optimize_correct {fl} {wcon : with_constructor_as_block = false} { Σ : GlobalContextMap.t} t v :
  wf_glob Σ ->
  @eval fl Σ t v ->
  wellformed Σ 0 t ->
  @eval fl (optimize_env Σ) (optimize Σ t) (optimize Σ v).
Proof.
  intros wfΣ ev.
  induction ev; simpl in *.

  - move/andP => [] cla clt. econstructor; eauto.
  - move/andP => [] clf cla.
    eapply eval_wellformed in ev2; tea => //.
    eapply eval_wellformed in ev1; tea => //.
    econstructor; eauto.
    rewrite -(optimize_csubst _ 1) //.
    apply IHev3. eapply wellformed_csubst => //.

  - move/andP => [] clb0 clb1.
    intuition auto.
    eapply eval_wellformed in ev1; tea => //.
    forward IHev2 by eapply wellformed_csubst => //.
    econstructor; eauto. rewrite -(optimize_csubst _ 1) //.

  - move/andP => [] /andP[] hl wfd wfbrs. rewrite optimize_mkApps in IHev1.
    eapply eval_wellformed in ev1 => //.
    move/wf_mkApps: ev1 => [] wfc' wfargs.
    eapply nth_error_forallb in wfbrs; tea.
    rewrite Nat.add_0_r in wfbrs.
    forward IHev2. eapply wellformed_iota_red; tea => //.
    rewrite optimize_iota_red in IHev2 => //. now rewrite e4.
    econstructor; eauto.
    rewrite -is_propositional_cstr_optimize //. tea.
    rewrite nth_error_map e2 //. len. len.

  - congruence.

  - move/andP => [] /andP[] hl wfd wfbrs.
    forward IHev2. eapply wellformed_substl; tea => //.
    rewrite forallb_repeat //. len.
    rewrite e1 /= Nat.add_0_r in wfbrs. now move/andP: wfbrs.
    rewrite optimize_substl in IHev2 => //.
    rewrite forallb_repeat //. len.
    rewrite e1 /= Nat.add_0_r in wfbrs. now move/andP: wfbrs.
    eapply eval_iota_sing => //; eauto.
    rewrite -is_propositional_optimize //.
    rewrite e1 //. simpl.
    rewrite map_repeat in IHev2 => //.

  - move/andP => [] clf cla. rewrite optimize_mkApps in IHev1.
    simpl in *.
    eapply eval_wellformed in ev1 => //.
    move/wf_mkApps: ev1 => [] wff wfargs.
    eapply eval_fix; eauto.
    rewrite map_length.
    eapply optimize_cunfold_fix; tea.
    rewrite optimize_mkApps in IHev3. apply IHev3.
    rewrite wellformed_mkApps // wfargs.
    eapply eval_wellformed in ev2; tas => //. rewrite ev2 /= !andb_true_r.
    eapply wellformed_cunfold_fix; tea.

  - move/andP => [] clf cla.
    eapply eval_wellformed in ev1 => //.
    move/wf_mkApps: ev1 => [] clfix clargs.
    eapply eval_wellformed in ev2; tas => //.
    rewrite optimize_mkApps in IHev1 |- *.
    simpl in *. eapply eval_fix_value. auto. auto. auto.
    eapply optimize_cunfold_fix; eauto.
    now rewrite map_length.

  - move/andP => [] clf cla.
    eapply eval_wellformed in ev1 => //.
    eapply eval_wellformed in ev2; tas => //.
    simpl in *. eapply eval_fix'. auto. auto.
    eapply optimize_cunfold_fix; eauto.
    eapply IHev2; tea. eapply IHev3.
    apply/andP; split => //.
    eapply wellformed_cunfold_fix; tea. now cbn.

  - move/andP => [] /andP[] hl cd clbrs. specialize (IHev1 cd).
    eapply eval_wellformed in ev1; tea => //.
    move/wf_mkApps: ev1 => [] wfcof wfargs.
    forward IHev2.
    rewrite hl wellformed_mkApps // /= wfargs clbrs !andb_true_r.
    eapply wellformed_cunfold_cofix; tea => //.
    rewrite !optimize_mkApps /= in IHev1, IHev2.
    eapply eval_cofix_case. tea.
    eapply optimize_cunfold_cofix; tea.
    exact IHev2.

  - move/andP => [] hl hd.
    rewrite GlobalContextMap.lookup_projection_spec in IHev2 |- *.
    destruct lookup_projection as [[[[mdecl idecl] cdecl] pdecl]|] eqn:hl' => //.
    eapply eval_wellformed in ev1 => //.
    move/wf_mkApps: ev1 => [] wfcof wfargs.
    forward IHev2.
    { rewrite /= wellformed_mkApps // wfargs andb_true_r.
      eapply wellformed_cunfold_cofix; tea. }
    rewrite optimize_mkApps /= in IHev1.
    eapply eval_cofix_case. eauto.
    eapply optimize_cunfold_cofix; tea.
    rewrite optimize_mkApps in IHev2 => //.

  - rewrite /declared_constant in isdecl.
    move: (lookup_env_optimize c wfΣ).
    rewrite isdecl /= //.
    intros hl.
    econstructor; tea. cbn. rewrite e //.
    apply IHev.
    eapply lookup_env_wellformed in wfΣ; tea.
    move: wfΣ. rewrite /wf_global_decl /= e //.

  - move=> /andP[] iss cld.
    rewrite GlobalContextMap.lookup_projection_spec.
    eapply eval_wellformed in ev1; tea => //.
    move/wf_mkApps: ev1 => [] wfc wfargs.
    destruct lookup_projection as [[[[mdecl idecl] cdecl'] pdecl]|] eqn:hl' => //.
    pose proof (lookup_projection_lookup_constructor hl').
    rewrite (constructor_isprop_pars_decl_constructor H) in e1. noconf e1.
    forward IHev1 by auto.
    forward IHev2. eapply nth_error_forallb in wfargs; tea.
    rewrite optimize_mkApps /= in IHev1.
    eapply eval_iota; tea.
    rewrite /constructor_isprop_pars_decl -lookup_constructor_optimize // H //= //.
    rewrite H0 H1; reflexivity. cbn. reflexivity. len. len.
    rewrite skipn_length. lia.
    unfold iota_red. cbn.
    rewrite (substl_rel _ _ (optimize Σ a)) => //.
    { eapply nth_error_forallb in wfargs; tea.
      eapply wf_optimize in wfargs => //.
      now eapply wellformed_closed in wfargs. }
    pose proof (wellformed_projection_args wfΣ hl'). cbn in H1.
    rewrite nth_error_rev. len. rewrite skipn_length. lia.
    rewrite List.rev_involutive. len. rewrite skipn_length.
    rewrite nth_error_skipn nth_error_map.
    rewrite e2 -H1.
    assert((ind_npars mdecl + cstr_nargs cdecl - ind_npars mdecl) = cstr_nargs cdecl) by lia.
    rewrite H3.
    eapply (f_equal (option_map (optimize Σ))) in e3.
    cbn in e3. rewrite -e3. f_equal. f_equal. lia.

  - congruence.

  - move=> /andP[] iss cld.
    rewrite GlobalContextMap.lookup_projection_spec.
    destruct lookup_projection as [[[[mdecl idecl] cdecl'] pdecl]|] eqn:hl' => //.
    pose proof (lookup_projection_lookup_constructor hl').
    simpl in H.
    move: e0. rewrite /inductive_isprop_and_pars.
    rewrite (lookup_constructor_lookup_inductive H) /=.
    intros [= eq <-].
    eapply eval_iota_sing => //; eauto.
    rewrite -is_propositional_optimize // /inductive_isprop_and_pars
      (lookup_constructor_lookup_inductive H) //=. congruence.
    have lenarg := wellformed_projection_args wfΣ hl'.
    rewrite (substl_rel _ _ tBox) => //.
    { rewrite nth_error_repeat //. len. }
    now constructor.

  - move/andP=> [] clf cla.
    rewrite optimize_mkApps.
    eapply eval_construct; tea.
    rewrite -lookup_constructor_optimize //. exact e0.
    rewrite optimize_mkApps in IHev1. now eapply IHev1.
    now len.
    now eapply IHev2.

  - congruence.

  - move/andP => [] clf cla.
    specialize (IHev1 clf). specialize (IHev2 cla).
    eapply eval_app_cong; eauto.
    eapply eval_to_value in ev1.
    destruct ev1; simpl in *; eauto.
    * depelim a0.
      + destruct t => //; rewrite optimize_mkApps /=.
      + now rewrite /= !orb_false_r orb_true_r in i.
    * destruct with_guarded_fix.
      + move: i.
        rewrite !negb_or.
        rewrite optimize_mkApps !isFixApp_mkApps !isConstructApp_mkApps !isPrimApp_mkApps.
        destruct args using rev_case => // /=. rewrite map_app !mkApps_app /= //.
        rewrite !andb_true_r.
        rtoProp; intuition auto;  destruct v => /= //.
      + move: i.
        rewrite !negb_or.
        rewrite optimize_mkApps !isConstructApp_mkApps !isPrimApp_mkApps.
        destruct args using rev_case => // /=. rewrite map_app !mkApps_app /= //.
        destruct v => /= //.
  - intros; rtoProp; intuition eauto.
    depelim X; repeat constructor.
    eapply All2_over_undep in a.
    eapply All2_Set_All2 in ev. eapply All2_All2_Set. primProp.
    subst a0 a'; cbn in *. depelim H0; cbn in *. intuition auto; solve_all.
    primProp; depelim H0; intuition eauto.
  - destruct t => //.
    all:constructor; eauto.
    cbn [atom optimize] in i |- *.
    rewrite -lookup_constructor_optimize //.
    destruct args; cbn in *; eauto.
Qed.

From MetaCoq.Erasure Require Import EEtaExpanded.

Lemma optimize_expanded {Σ : GlobalContextMap.t} t : expanded Σ t -> expanded Σ (optimize Σ t).
Proof.
  induction 1 using expanded_ind.
  all:try solve[constructor; eauto; solve_all].
  all:rewrite ?optimize_mkApps.
  - eapply expanded_mkApps_expanded => //. solve_all.
  - cbn -[GlobalContextMap.inductive_isprop_and_pars].
    rewrite GlobalContextMap.lookup_projection_spec.
    destruct lookup_projection as [[[[mdecl idecl] cdecl] pdecl]|] => /= //.
    2:constructor; eauto; solve_all.
    destruct proj as [[ind npars] arg].
    econstructor; eauto. repeat constructor.
  - cbn. eapply expanded_tFix. solve_all.
    rewrite isLambda_optimize //.
  - eapply expanded_tConstruct_app; tea.
    now len. solve_all.
Qed.

Lemma optimize_expanded_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} t : wf_glob Σ -> expanded Σ t -> expanded (optimize_env Σ) t.
Proof.
  intros wf; induction 1 using expanded_ind.
  all:try solve[constructor; eauto; solve_all].
  eapply expanded_tConstruct_app.
  destruct H as [[H ?] ?].
  split => //. split => //. red.
  red in H. rewrite lookup_env_optimize // /= H //. 1-2:eauto. auto. solve_all.
Qed.

Lemma optimize_expanded_decl {Σ : GlobalContextMap.t} t : expanded_decl Σ t -> expanded_decl Σ (optimize_decl Σ t).
Proof.
  destruct t as [[[]]|] => /= //.
  unfold expanded_constant_decl => /=.
  apply optimize_expanded.
Qed.

Lemma optimize_expanded_decl_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} t : wf_glob Σ -> expanded_decl Σ t -> expanded_decl (optimize_env Σ) t.
Proof.
  destruct t as [[[]]|] => /= //.
  unfold expanded_constant_decl => /=.
  apply optimize_expanded_irrel.
Qed.

Lemma optimize_wellformed_term {efl : EEnvFlags} {Σ : GlobalContextMap.t} n t :
  has_tBox -> has_tRel ->
  wf_glob Σ -> EWellformed.wellformed Σ n t ->
  EWellformed.wellformed (efl := disable_projections_env_flag efl) Σ n (optimize Σ t).
Proof.
  intros hbox hrel wfΣ.
  induction t in n |- * using EInduction.term_forall_list_ind => //.
  all:try solve [cbn; rtoProp; intuition auto; solve_all].
  - cbn -[lookup_constructor_pars_args]. intros. rtoProp. repeat split; eauto.
    destruct cstr_as_blocks; rtoProp; eauto.
    destruct lookup_constructor_pars_args as [ [] | ]; eauto. split; len.  solve_all. split; eauto.
    solve_all. now destruct args; invs H0.
  - cbn. move/andP => [] /andP[] hast hl wft.
    rewrite GlobalContextMap.lookup_projection_spec.
    destruct lookup_projection as [[[[mdecl idecl] cdecl] pdecl]|] eqn:hl'; auto => //.
    simpl.
    rewrite (lookup_constructor_lookup_inductive (lookup_projection_lookup_constructor hl')) /=.
    rewrite hrel IHt //= andb_true_r.
    have hargs' := wellformed_projection_args wfΣ hl'.
    apply Nat.ltb_lt. len.
  - cbn. unfold wf_fix; rtoProp; intuition auto; solve_all. now eapply isLambda_optimize.
  - cbn. unfold wf_fix; rtoProp; intuition auto; solve_all.
  - cbn. rtoProp; intuition eauto; solve_all_k 6.
Qed.

Import EWellformed.

Lemma optimize_wellformed_irrel {efl : EEnvFlags} {Σ : GlobalContextMap.t} t :
  wf_glob Σ ->
  forall n, wellformed (efl := disable_projections_env_flag efl) Σ n t ->
  wellformed (efl := disable_projections_env_flag efl) (optimize_env Σ) n t.
Proof.
  intros wfΣ. induction t using EInduction.term_forall_list_ind; cbn => //.
  all:try solve [intros; unfold wf_fix_gen in *; rtoProp; intuition eauto; solve_all].
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //.
    repeat (rtoProp; intuition auto).
    destruct has_axioms => //. cbn in *.
    destruct (cst_body c) => //.
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=; intros; rtoProp; eauto.
    destruct g eqn:hg => /= //; intros; rtoProp; eauto.
    repeat split; eauto. destruct cstr_as_blocks; rtoProp; repeat split; eauto. solve_all.
  - rewrite lookup_env_optimize //.
    destruct lookup_env eqn:hl => // /=.
    destruct g eqn:hg => /= //. subst g.
    destruct nth_error => /= //.
    intros; rtoProp; intuition auto; solve_all.
Qed.

Lemma optimize_wellformed {efl : EEnvFlags} {Σ : GlobalContextMap.t} n t :
  has_tBox -> has_tRel ->
  wf_glob Σ -> EWellformed.wellformed Σ n t ->
  EWellformed.wellformed (efl := disable_projections_env_flag efl) (optimize_env Σ) n (optimize Σ t).
Proof.
  intros. apply optimize_wellformed_irrel => //.
  now apply optimize_wellformed_term.
Qed.

From MetaCoq.Erasure Require Import EGenericGlobalMap.

#[local]
Instance GT : GenTransform := { gen_transform := optimize; gen_transform_inductive_decl := id }.
#[local]
Instance GTID : GenTransformId GT.
Proof.
  red. reflexivity.
Qed.
#[local]
Instance GTExt efl : GenTransformExtends efl (disable_projections_env_flag efl) GT.
Proof.
  intros Σ t n wfΣ Σ' ext wf wf'.
  unfold gen_transform, GT.
  eapply wellformed_optimize_extends; tea.
Qed.
#[local]
Instance GTWf efl : GenTransformWf efl (disable_projections_env_flag efl) GT.
Proof.
  refine {| gen_transform_pre := fun _ _ => has_tBox /\ has_tRel |}; auto.
  intros Σ n t [] wfΣ wft.
  now apply optimize_wellformed.
Defined.

Lemma optimize_extends_env {efl : EEnvFlags} {Σ Σ' : GlobalContextMap.t} :
  has_tApp ->
  extends Σ Σ' ->
  wf_glob Σ ->
  wf_glob Σ' ->
  extends (optimize_env Σ) (optimize_env Σ').
Proof.
  intros hast ext wf.
  now apply (gen_transform_extends (gt := GTExt efl) ext).
Qed.

Lemma optimize_env_eq {efl : EEnvFlags} (Σ : GlobalContextMap.t) : wf_glob Σ -> optimize_env Σ = optimize_env' Σ.(GlobalContextMap.global_decls) Σ.(GlobalContextMap.wf).
Proof.
  intros wf.
  now apply (gen_transform_env_eq (gt := GTExt efl)).
Qed.

Lemma optimize_env_expanded {efl : EEnvFlags} {Σ : GlobalContextMap.t} :
  wf_glob Σ -> expanded_global_env Σ -> expanded_global_env (optimize_env Σ).
Proof.
  unfold expanded_global_env; move=> wfg.
  rewrite optimize_env_eq //.
  destruct Σ as [Σ map repr wf]. cbn in *.
  clear map repr.
  induction 1; cbn; constructor; auto.
  cbn in IHexpanded_global_declarations.
  unshelve eapply IHexpanded_global_declarations. now depelim wfg. cbn.
  set (Σ' := GlobalContextMap.make _ _).
  rewrite -(optimize_env_eq Σ'). cbn. now depelim wfg.
  eapply (optimize_expanded_decl_irrel (Σ := Σ')). now depelim wfg.
  now unshelve eapply (optimize_expanded_decl (Σ:=Σ')).
Qed.

Lemma Pre_glob efl Σ wf :
  has_tBox -> has_tRel -> Pre_glob (GTWF:=GTWf efl) Σ wf.
Proof.
  intros hasb hasr.
  induction Σ => //. destruct a as [kn d]; cbn.
  split => //. destruct d as [[[|]]|] => //=.
Qed.

Lemma optimize_env_wf {efl : EEnvFlags} {Σ : GlobalContextMap.t} :
  has_tBox -> has_tRel ->
  wf_glob Σ -> wf_glob (efl := disable_projections_env_flag efl) (optimize_env Σ).
Proof.
  intros hasb hasre wfg.
  eapply (gen_transform_env_wf (gt := GTExt efl)) => //.
  now apply Pre_glob.
Qed.

Definition optimize_program (p : eprogram_env) :=
  (optimize_env p.1, optimize p.1 p.2).

Definition optimize_program_wf {efl : EEnvFlags} (p : eprogram_env) {hastbox : has_tBox} {hastrel : has_tRel} :
  wf_eprogram_env efl p -> wf_eprogram (disable_projections_env_flag efl) (optimize_program p).
Proof.
  intros []; split.
  now eapply optimize_env_wf.
  cbn. now eapply optimize_wellformed.
Qed.

Definition optimize_program_expanded {efl} (p : eprogram_env) :
  wf_eprogram_env efl p ->
  expanded_eprogram_env_cstrs p -> expanded_eprogram_cstrs (optimize_program p).
Proof.
  unfold expanded_eprogram_env_cstrs.
  move=> [wfe wft] /andP[] etae etat.
  apply/andP; split.
  cbn. eapply expanded_global_env_isEtaExp_env, optimize_env_expanded => //.
  now eapply isEtaExp_env_expanded_global_env.
  eapply expanded_isEtaExp.
  eapply optimize_expanded_irrel => //.
  now apply optimize_expanded, isEtaExp_expanded.
Qed.
