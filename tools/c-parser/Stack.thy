theory Stack
  imports Main
begin

text \<open>
  A Stack is a list of frames.
  In addition, each frame on the stack stores its generation, i.e. the number of times that depth
  of frame has been reached. For example, pushing the frame \<open>c\<close> onto
    (2, a) \<triangleright> (1, b) \<triangleright> Top 1
  will result in the stack
    (2, a) \<triangleright> (1, b) \<triangleright> (1, c) \<triangleright> Top 0.
  Popping a frame from the above stack will result in the stack
    (2, a) \<triangleright> (1, b) \<triangleright> Top 2.
\<close>
datatype 'a stack
  = Frame "nat \<times> 'a" "'a stack" (infixr "\<triangleright>" 65)
  | Top nat


text \<open>
  A stack pointer points to a particular path in a particular frame.
  Frames are parametrised by the 'f type variable, paths are parametrised by the 'a type variable.

  A stack pointer either points to the current frame \<open>ThisFrame\<close> or to a frame beneath this one
  \<open>DownFrame\<close>.

  Each variant keeps track of the generation of the frame it is supposed to be pointing to. This
  allows us to catch if the stack has changed, but we have an old pointer.
\<close>
datatype ('f,'a) stack_ptr
  = ThisFrame nat "'f \<Rightarrow> 'a" (* TODO needs to change *)
  | DownFrame nat "('f,'a) stack_ptr"

fun valid_stack_ptr :: "'f stack \<Rightarrow> ('f,'a) stack_ptr \<Rightarrow> bool" where
  "valid_stack_ptr ((g,_) \<triangleright> s) (DownFrame g' p) = ((g = g') \<and> valid_stack_ptr s p)"
| "valid_stack_ptr ((g,_) \<triangleright> _) (ThisFrame g' _) = (g = g')" (* TODO have to check path here *)
| "valid_stack_ptr (Top _) _ = False"

fun deref_stack_ptr :: "'f stack \<Rightarrow> ('f,'a) stack_ptr \<Rightarrow> 'a option" where
  "deref_stack_ptr ((g,f) \<triangleright> s) (DownFrame g' p) =
    (if g = g' then deref_stack_ptr s p else None)"
| "deref_stack_ptr ((g,f) \<triangleright> _) (ThisFrame g' prj) =
    (if g = g' then Some (prj f) else None)"
| "deref_stack_ptr _ _ = None"

(* The top of the stack, alas, needs to be at the end of the list structure *)

fun get_top_frame_stack :: "'f stack \<Rightarrow> 'f" where
  "get_top_frame_stack (fm \<triangleright> Top _) = snd fm"
| "get_top_frame_stack (_ \<triangleright> s) = get_top_frame_stack s"
| "get_top_frame_stack (Top _) = undefined"

fun top_frame_update_stack :: "('f \<Rightarrow> 'f) \<Rightarrow> 'f stack \<Rightarrow> 'f stack" where
  "top_frame_update_stack f (a \<triangleright> Top n) = (fst a, f (snd a)) \<triangleright> Top n"
| "top_frame_update_stack f (a \<triangleright> s) = a \<triangleright> top_frame_update_stack f s"
| "top_frame_update_stack _ (Top n) = Top n"

fun pop_stack :: "'f stack \<Rightarrow> 'f stack" where
  "pop_stack ((g,_) \<triangleright> Top _) = Top (Suc g)"
| "pop_stack (a \<triangleright> s) = a \<triangleright> pop_stack s"
| "pop_stack (Top _) = undefined"

fun push_stack :: "'f \<Rightarrow> 'f stack \<Rightarrow> 'f stack" where
  "push_stack fm (a \<triangleright> s) = a \<triangleright> push_stack fm s"
| "push_stack fm (Top g) = (g, fm) \<triangleright> Top 0"

fun next_gen_update_stack :: "(nat \<Rightarrow> nat) \<Rightarrow> 'f stack \<Rightarrow> 'f stack" where
  "next_gen_update_stack f (Top g) = Top (f g)"
| "next_gen_update_stack f (a \<triangleright> s) = a \<triangleright> next_gen_update_stack f s"


definition stack_empty :: "'f stack \<Rightarrow> bool" where
  "stack_empty s \<equiv> \<exists>k. s = Top k"

lemma stack_empty_simps[simp]:
  \<open>stack_empty (Top g) = True\<close>
  \<open>stack_empty (a \<triangleright> s) = False\<close>
  by (simp add: stack_empty_def)+

lemma stack_pop_push[simp]:
  "pop_stack (push_stack fm s) = next_gen_update_stack Suc s"
  by (induct s rule: pop_stack.induct) clarsimp+

lemma next_gen_update_next_gen_update[simp]:
  "next_gen_update_stack f (next_gen_update_stack g s) = next_gen_update_stack (f \<circ> g) s"
  by (induct s) clarsimp+

lemma top_frame_same_under_next_gen_update[simp]:
  "get_top_frame_stack (next_gen_update_stack f s) = get_top_frame_stack s"
  by (induct s rule: get_top_frame_stack.induct) simp+


lemma top_frame_update_stack_on_push':
  "fm' = f fm \<Longrightarrow> top_frame_update_stack f (push_stack fm s) = push_stack fm' s"
  apply (induct s rule: push_stack.induct)
   apply (case_tac s; force)
  apply force
  done

lemma top_frame_update_stack_on_push[simp]:
  "top_frame_update_stack f (push_stack fm s) = push_stack (f fm) s"
  by (simp add: top_frame_update_stack_on_push')

lemma get_top_frame_of_update:
  assumes \<open>\<not> stack_empty s\<close>
  shows \<open>get_top_frame_stack (top_frame_update_stack f s) = f (get_top_frame_stack s)\<close>
  using assms
  apply (induct s rule: get_top_frame_stack.induct)
    apply clarsimp
   apply clarsimp
  apply (rename_tac a n s)
   apply (case_tac s)
    apply clarsimp
   apply clarsimp
  apply clarsimp
  done


lemma top_frame_update_stack_preserves_structure:
  "top_frame_update_stack f (a \<triangleright> s) =
    (case s of
      Top n \<Rightarrow> (fst a, f (snd a))
    | _ \<Rightarrow> a)
    \<triangleright>
    (case s of
      Top n \<Rightarrow> Top n
    | _ \<Rightarrow> top_frame_update_stack f s)"
  "top_frame_update_stack f (Top n) = Top n"
  by (cases s; simp) simp

lemma top_frame_update_merge[simp]:
  "top_frame_update_stack f (top_frame_update_stack g s) = top_frame_update_stack (\<lambda>x. f (g x)) s"
  apply (induct s)
   apply (case_tac s)
    apply (force simp add: top_frame_update_stack_preserves_structure)+
  done

lemma next_gen_update_top_frame_update_norm[simp]:
  "next_gen_update_stack f (top_frame_update_stack g s)
  = top_frame_update_stack g (next_gen_update_stack f s)"
  apply (induct s)
   apply (case_tac s; simp)
  apply simp
  done

lemma next_gen_update_empty[simp]:
  "stack_empty (next_gen_update_stack f s) \<longleftrightarrow> stack_empty s"
  by (induct s) (simp add: stack_empty_def)+

lemma next_gen_update_nonempty[simp]:
  "\<not> stack_empty (next_gen_update_stack f s) \<longleftrightarrow> \<not> stack_empty s"
  by (induct s) (simp add: stack_empty_def)+

end