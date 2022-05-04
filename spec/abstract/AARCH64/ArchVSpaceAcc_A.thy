(*
 * Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
 * Copyright 2022, Proofcraft Pty Ltd
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *)

chapter "Accessing the AARCH64 VSpace"

theory ArchVSpaceAcc_A
imports KHeap_A
begin

context Arch begin global_naming AARCH64_A

text \<open>
  This part of the specification is fairly concrete as the machine architecture is visible to
  the user in seL4 and therefore needs to be described. The abstraction compared to the
  implementation is in the data types for kernel objects. The interface which is rich in machine
  details remains the same.
\<close>

section "Encodings"

text \<open>The high bits of a virtual ASID.\<close>
definition asid_high_bits_of :: "asid \<Rightarrow> asid_high_index" where
  "asid_high_bits_of asid \<equiv> ucast (asid >> asid_low_bits)"

text \<open>The low bits of a virtual ASID.\<close>
definition asid_low_bits_of :: "asid \<Rightarrow> asid_low_index" where
  "asid_low_bits_of asid \<equiv> ucast asid"

lemmas asid_bits_of_defs = asid_high_bits_of_def asid_low_bits_of_def

locale_abbrev asid_table :: "'z::state_ext state \<Rightarrow> asid_high_index \<rightharpoonup> obj_ref" where
  "asid_table \<equiv> \<lambda>s. arm_asid_table (arch_state s)"

section "Kernel Heap Accessors"

(* declared in Arch as workaround for VER-1099 *)
locale_abbrev aobjs_of :: "'z::state_ext state \<Rightarrow> obj_ref \<rightharpoonup> arch_kernel_obj" where
  "aobjs_of \<equiv> \<lambda>s. kheap s |> aobj_of"

text \<open>Manipulate ASID pools, page directories and page tables in the kernel heap.\<close>

locale_abbrev asid_pools_of :: "'z::state_ext state \<Rightarrow> obj_ref \<rightharpoonup> asid_pool" where
  "asid_pools_of \<equiv> \<lambda>s. aobjs_of s |> asid_pool_of"

locale_abbrev get_asid_pool :: "obj_ref \<Rightarrow> (asid_pool, 'z::state_ext) s_monad" where
  "get_asid_pool \<equiv> gets_map asid_pools_of"

definition set_asid_pool :: "obj_ref \<Rightarrow> asid_pool \<Rightarrow> (unit,'z::state_ext) s_monad" where
  "set_asid_pool ptr pool \<equiv> do
     get_asid_pool ptr;
     set_object ptr (ArchObj (ASIDPool pool))
   od"

locale_abbrev pts_of :: "'z::state_ext state \<Rightarrow> obj_ref \<rightharpoonup> pt" where
  "pts_of \<equiv> \<lambda>s. aobjs_of s |> pt_of"

locale_abbrev get_pt :: "obj_ref \<Rightarrow> (pt,'z::state_ext) s_monad" where
  "get_pt \<equiv> gets_map pts_of"

definition set_pt :: "obj_ref \<Rightarrow> pt \<Rightarrow> (unit,'z::state_ext) s_monad" where
  "set_pt ptr pt \<equiv> do
     get_pt ptr;
     set_object ptr (ArchObj (PageTable pt))
   od"

text \<open>The base address of the table a page table entry at p is in (assuming alignment)\<close>
locale_abbrev table_base :: "bool \<Rightarrow> obj_ref \<Rightarrow> obj_ref" where
  "table_base is_vspace p \<equiv> p && ~~mask (pt_bits is_vspace)"

text \<open>The index within the page table that a page table entry at p addresses\<close>
locale_abbrev table_index :: "bool \<Rightarrow> obj_ref \<Rightarrow> 'a::len word" where
  "table_index is_vspace p \<equiv> ucast (p && mask (pt_bits is_vspace) >> pte_bits)"

locale_abbrev vsroot_index :: "obj_ref \<Rightarrow> vs_index" where
  "vsroot_index \<equiv> table_index True"

locale_abbrev ptable_index :: "obj_ref \<Rightarrow> pt_index" where
  "ptable_index \<equiv> table_index False"

definition pt_pte :: "pt \<Rightarrow> obj_ref \<Rightarrow> pte" where
  "pt_pte pt p \<equiv> case pt of
                   VSRootPT vs \<Rightarrow> vs (vsroot_index p)
                 | NormalPT pt \<Rightarrow> pt (ptable_index p)"

text \<open>Extract a PTE from the page table of a specific level\<close>
definition level_pte_of :: "bool \<Rightarrow> obj_ref \<Rightarrow> (obj_ref \<rightharpoonup> pt) \<rightharpoonup> pte" where
  "level_pte_of is_vspace p \<equiv> do {
      oassert (is_aligned p pte_bits);
      pt \<leftarrow> oapply (table_base is_vspace p);
      oassert (is_vspace = is_VSRootPT pt);
      oreturn $ pt_pte pt p
   }"

(* pte from page tables of any level = map-union of all levels, since we can assume distinctness *)
definition pte_of :: "(obj_ref \<rightharpoonup> pt) \<Rightarrow> obj_ref \<rightharpoonup> pte" where
  "pte_of s \<equiv> swp (level_pte_of True) s ++ swp (level_pte_of False) s"

locale_abbrev ptes_of :: "'z::state_ext state \<Rightarrow> obj_ref \<rightharpoonup> pte" where
  "ptes_of s \<equiv> pte_of (pts_of s)"


text \<open>The following function takes a pointer to a PTE in kernel memory and returns the PTE.\<close>
locale_abbrev get_pte :: "obj_ref \<Rightarrow> (pte,'z::state_ext) s_monad" where
  "get_pte \<equiv> gets_map ptes_of"

definition pt_upd :: "pt \<Rightarrow> obj_ref \<Rightarrow> pte \<Rightarrow> pt" where
  "pt_upd pt p pte \<equiv> case pt of
                       VSRootPT vs \<Rightarrow> VSRootPT (vs(vsroot_index p := pte))
                     | NormalPT pt \<Rightarrow> NormalPT (pt(ptable_index p := pte))"

(* Checks object content so that this also works when object sizes are equal between levels. *)
definition pt_level_of :: "obj_ref \<Rightarrow> (obj_ref \<rightharpoonup> pt) \<Rightarrow> bool" where
  "pt_level_of p pts \<equiv> \<exists>pt. pts (table_base True p) = Some (VSRootPT pt)"

(* Determine which level the pt object is, then update. *)
definition store_pte :: "obj_ref \<Rightarrow> pte \<Rightarrow> (unit,'z::state_ext) s_monad" where
  "store_pte p pte \<equiv> do
     assert (is_aligned p pte_bits);
     is_vspace \<leftarrow> gets (pt_level_of p \<circ> pts_of);
     base \<leftarrow> return $ table_base is_vspace p;
     pt \<leftarrow> get_pt base;
     set_pt base (pt_upd pt p pte)
   od"


section "Basic Operations"

(* During pt_walk, we will only call this with level \<le> max_pt_level, but in the invariants we
   also make use of this function for level = asid_pool_level. *)
definition pt_bits_left :: "vm_level \<Rightarrow> nat" where
  "pt_bits_left level =
    (if level = asid_pool_level
     then ptTranslationBits True + ptTranslationBits False * size max_pt_level
     else ptTranslationBits False * size level)
    + pageBits"

definition pt_index :: "vm_level \<Rightarrow> vspace_ref \<Rightarrow> machine_word" where
  "pt_index level vptr \<equiv>
     (vptr >> pt_bits_left level) && mask (ptTranslationBits (level = max_pt_level))"


locale_abbrev global_pt :: "'z state \<Rightarrow> obj_ref" where
  "global_pt s \<equiv> arm_us_global_vspace (arch_state s)"


subsection \<open>Walk page tables in software.\<close>

definition pptr_from_pte :: "pte \<Rightarrow> vspace_ref" where
  "pptr_from_pte pte \<equiv> ptrFromPAddr (pte_base_addr pte)"

definition pt_slot_offset :: "vm_level \<Rightarrow> obj_ref \<Rightarrow> vspace_ref \<Rightarrow> obj_ref" where
  "pt_slot_offset level pt_ptr vptr = pt_ptr + (pt_index level vptr << pte_bits)"

text \<open>
  This is the base function for walking a page table structure.
  The walk proceeds from higher-level tables at the provided @{term level} (e.g. 2) to lower
  level tables, down to @{term bot_level} (e.g. 0). It returns a pointer to the page table where
  the walk stopped and the level of that table. The lookup stops when @{term bot_level} or a
  page is reached.
\<close>
fun pt_walk ::
  "vm_level \<Rightarrow> vm_level \<Rightarrow> obj_ref \<Rightarrow> vspace_ref \<Rightarrow> (obj_ref \<rightharpoonup> pte) \<Rightarrow> (vm_level \<times> obj_ref) option"
  where
  "pt_walk level bot_level pt_ptr vptr = do {
     if bot_level < level
     then do {
       pte \<leftarrow> oapply (pt_slot_offset level pt_ptr vptr);
       if is_PageTablePTE pte
         then pt_walk (level - 1) bot_level (pptr_from_pte pte) vptr
         else oreturn (level, pt_ptr)
     }
     else oreturn (level, pt_ptr)
   }"

declare pt_walk.simps[simp del]

text \<open>
  Looking up a slot in a page table structure. The function returns a level and an object
  pointer. The pointer is to a slot in a table at the returned level. If the returned level is 0,
  this slot is either an @{const InvalidPTE} or a @{const PagePTE}. If the returned level is higher
  the slot may also be a @{const PageTablePTE}.
\<close>
definition pt_lookup_slot_from_level ::
  "vm_level \<Rightarrow> vm_level \<Rightarrow> obj_ref \<Rightarrow> vspace_ref \<Rightarrow> (obj_ref \<rightharpoonup> pte) \<Rightarrow> (vm_level \<times> obj_ref) option"
  where
  "pt_lookup_slot_from_level level bot_level pt_ptr vptr = do {
     (level', pt_ptr') \<leftarrow> pt_walk level bot_level pt_ptr vptr;
     oreturn (level', pt_slot_offset level' pt_ptr' vptr)
   }"

definition pt_lookup_slot :: "obj_ref \<Rightarrow> vspace_ref \<Rightarrow> (obj_ref \<rightharpoonup> pte) \<Rightarrow> (vm_level \<times> obj_ref) option"
  where
  "pt_lookup_slot = pt_lookup_slot_from_level max_pt_level 0"

text \<open>Returns the slot that points to @{text target_pt_ptr}\<close>
fun pt_lookup_from_level ::
  "vm_level \<Rightarrow> obj_ref \<Rightarrow> vspace_ref \<Rightarrow> obj_ref \<Rightarrow> (machine_word, 'z::state_ext) lf_monad"
  where
  "pt_lookup_from_level level pt_ptr vptr target_pt_ptr s = (doE
     unlessE (0 < level) $ throwError InvalidRoot;
     slot <- returnOk $ pt_slot_offset level pt_ptr vptr;
     pte <- liftE $ gets_the $ oapply slot o ptes_of;
     unlessE (is_PageTablePTE pte) $ throwError InvalidRoot;
     ptr <- returnOk (pptr_from_pte pte);
     if ptr = target_pt_ptr
       then returnOk slot
       else pt_lookup_from_level (level - 1) ptr vptr target_pt_ptr
   odE) s"
(* We apply "s" to avoid a type variable warning, and increase in global freeindex counter,
   which we would get without the application *)

declare pt_lookup_from_level.simps[simp del]

(* Recover simp rule without state applied: *)
schematic_goal pt_lookup_from_level_simps:
  "pt_lookup_from_level level pt_ptr vptr target_pt_ptr = ?rhs"
  by (rule ext, rule pt_lookup_from_level.simps)

end
end
