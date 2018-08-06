(*
 * Copyright 2018, Data61, CSIRO
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(DATA61_GPL)
 *)

chapter \<open>Arch IPC Cancelling\<close>

theory ArchIpcCancel_A
imports "../CSpaceAcc_A"
begin

context Arch begin global_naming RISCV64_A

text \<open>Actions to be taken after a cap is deleted\<close>
definition arch_post_cap_deletion :: "arch_cap \<Rightarrow> (unit, 'z::state_ext) s_monad"
  where
  "arch_post_cap_deletion ac \<equiv> return ()"

text \<open>Arch specific generic object references not covered by generic references\<close>
datatype arch_gen_obj_ref = unit

definition arch_gen_obj_refs :: "arch_cap \<Rightarrow> arch_gen_obj_ref set"
  where
  "arch_gen_obj_refs ac \<equiv> {}"

definition arch_cap_cleanup_opt :: "arch_cap \<Rightarrow> cap"
  where
  "arch_cap_cleanup_opt ac \<equiv> NullCap"

end
end
