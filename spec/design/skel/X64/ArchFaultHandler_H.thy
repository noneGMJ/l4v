(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

chapter "Fault Handlers"

theory ArchFaultHandler_H
imports "../TCB_H" "../Structures_H"
begin

context Arch begin global_naming X64_H

#INCLUDE_HASKELL_PREPARSE SEL4/API/Failures/X64.lhs

#INCLUDE_HASKELL SEL4/API/Faults/X64.lhs decls_only
#INCLUDE_HASKELL SEL4/API/Faults/X64.lhs bodies_only

end

end
