<!--
     Copyright 2021, Data61, CSIRO (ABN 41 687 119 230)

     SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture Split

The problem that architecture splitting ("arch_split") seeks to address is
separating architecture-generic concepts from architecture-specific concepts in
the proofs. Ultimately, arch_split aims to find suitable abstractions of
architecture-specific details, so that we may prove architecture-generic lemmas
without unfolding architecture-specific definitions, and therefore share
architecture-generic proofs across multiple architectures. But we're not there
yet. So far only the `ASpec` and `AInvs` sessions have really been split.

We use (perhaps abuse) the Isabelle locale mechanism, together with some custom
commands, to place architecture-specific definitions and proofs in namespaces,
to make it harder to unfold architecture-specific definitions by accident. We
also have a collection of hacks to keep existing proofs checking while we
continue to work towards the ultimate goal of proofs on multiple architectures.

This file describes the current state of arch_split, and what still needs to be
done.

## L4V_ARCH

The architecture split is controlled by an environment
variable, `L4V_ARCH`, which is used in theory imports sections to include
the appropriate architecture-specific theory for the currently selected
architecture. For example:

- `l4v/spec/abstract/CSpace_A.thy`

```isabelle
theory CSpace_A
imports
  "./$L4V_ARCH/ArchVSpace_A"
  IpcCancel_A
  "./$L4V_ARCH/ArchCSpace_A"
```

For the `ARM` architecture, we make subdirectories named `ARM` for
architecture-specific theories, and set `L4V_ARCH=ARM` in the environment before
starting Isabelle.

Theories often come in pairs of a generic theory and an associated
architecture-specific theory. Since theory base names must be unique, regardless
of their fully qualified names, we adopt the convention that
architecture-specific theory names are prefixed with "Arch". We don't prefix
with `ARM` or `X64`, because generic theories must be able to import
architecture-specific theories without naming a particular architecture.

## The Arch locale

We use a locale named `Arch` as a container for architecture-specific
definitions and lemmas, defined as follows:

- `l4v/spec/machine/Setup_Locale.thy`

```isabelle
theory Setup_Locale
imports "../../lib/Qualify" "../../lib/Requalify" "../../lib/Extend_Locale"
begin
(*
   We use a locale for namespacing architecture-specific definitions.
   The global_naming command changes the underlying naming of the locale. The intention is that
   we liberally put everything into the "ARM" namespace, and then carefully unqualify (put into global namespace)
   or requalify (change qualifier to "Arch" instead of "ARM") in order to refer to entities in
   generic proofs.
*)
locale Arch
end
```

All architecture-specific definitions should be placed in the Arch locale, with
an appropriate global_naming scheme (see below).

If you're not familiar with locales, you should read the [locale tutorial]. The
`Arch` locale has no parameters and no assumptions, since we are merely using it
as a namespace, but it still important to understand the various ways of
interpreting this locale, how it interacts with various other locales in the
proofs, as well as our custom name-spacing commands.

The locale is named "Arch" on every architectures, rather than "ARM" or "X64",
because the generic theories need to be able to selectively refer to types,
constants and facts from architecture-specific theories, without naming a
particular architecture. The mechanisms for doing this are described below.

[locale tutorial]: https://isabelle.in.tum.de/website-Isabelle2021/dist/Isabelle2021/doc/locales.pdf

## Current status

The sessions `ASpec` and `AInvs` are split, but other proofs remain duplicated
between architectures.

As a temporary measure, we wrap existing proofs in an anonymous context block,
in which we interpret the Arch locale. For example:

```isabelle
theory Retype_R
imports VSpace_R
begin

context begin interpretation Arch . (*FIXME: arch_split*)

lemma placeNewObject_def2:
 "placeNewObject ptr val gb = createObjects' ptr 1 (injectKO val) gb"
   apply (clarsimp simp:placeNewObject_def placeNewObject'_def
     createObjects'_def shiftL_nat)
  done

(* ... *)
end
end
```

The `FIXME` indicates that this is a temporary workaround, and that
architecture-specific proofs still need to be separated out before this part of
the proof can be adapted to another architecture.

There are issues with some commands that do not work inside anonymous context
blocks, most notably locale declarations, and locale context blocks. In these
cases, we exit the anonymous context block before entering the locale context,
and then interpret the Arch locale inside the locale context block (if necessary).

## Global naming

Even though the Arch locale must have the same name on every architecture, we
need a way to distinguish between architecture-dependent types, constants and
lemmas which are expected to exist on every architecture, and those which are
internal to a particular architecture. We want to be able to *refer* to the
former in generic theories, while acknowledging that they have
architecture-specific definitions and proofs. But we want to prevent ourselves
from inadvertently referring to types, constants and facts which are only
internal to a particular architecture, for example, definitions of constants.

To help achieve this hiding, we provide a custom command, **global_naming**,
that modifies the way qualified names are generated. The primary use of
`global_naming` is in architecture-specific theories, to ensure that by default,
types, constants and lemmas are given an architecture-specific qualified name,
even though they are part of the Arch locale.

- `l4v/proof/invariant-abstract/ARM/ArchADT_AI.thy`

```isabelle
theory ArchADT_AI
imports "../Invariants_AI" (* ... *)
begin

(* All ARM-specific definitions and lemmas should be placed in the Arch context,
   with the "ARM" global_naming scheme. *)

context Arch begin global_naming ARM
definition "get_pd_of_thread ≡ ..."
end

(* Back in the global context, we can't refer to these names without naming a particular architecture! *)
term get_pd_of_thread         (* Free variable                                                              *)
term Arch.get_pd_of_thread    (* Free variable                                                              *)
term ARM.get_pd_of_thread     (* Accessible, and the qualifier clearly indicates that this is ARM-specific. *)
thm  ARM.get_pd_of_thread_def (* Also accessible.                                                           *)

(* ... *)
end
```

In the above example, we are in an `ARM`-specific theory in the abstract
invariants. We enter the `Arch` locale (`context Arch begin ... end`), and
immediately set the `global_naming` scheme for this context block to `ARM`.
Constants and lemmas in this context block are given their usual unqualified
local names in the `Arch` locale, but their global names are qualified as "ARM",
rather than "Arch". This means that outside the `Arch` context, we cannot refer
to these constants and lemmas without explicitly naming a particular
architecture. If we saw such a reference in a generic theory, we would
immediately recognise that something was wrong.

The convention is that in architecture-specific theories, we initially
give *all* types, constants and lemmas with an architecture-specific
`global_naming` scheme. Then, in generic theories, we use
*requalification* to selectively extract just those types, constants and
facts which are expected to exist on all architectures.

## Requalify

We provide three custom commands for giving existing names new bindings
in the global namespace: **requalify_types**, **requalify_consts**,
**requalify_facts**, for types, constants and facts respectively. The
new name is based on the context in which the requalification command is
executed. We use requalification in various ways, depending on the
situation.

The most basic use is to take a name from the Arch context and make it
available in the global context without qualification. This should be
done for any type, constant or fact:

1. which is expected to exist on all architectures, even though it is defined or
   proved differently on different architectures,

2. which is needed in architecture-generic definitions or proofs,

3. whose unqualified name does not clash with some other architecture-generic
   type, constant or fact, so that the unqualified name unambiguously denotes
   the architecture-specific concept for the current architecture.

We do this in a generic theory:

- `l4v/proof/invariant-abstract/ADT_AI.thy`

```isabelle
theory ADT_AI
imports
  "./$L4V_ARCH/ArchADT_AI"
begin

term empty_context (* Free variable. *)

context begin interpretation Arch .
term empty_context (* This was previously defined in the Arch locale. *)
requalify_consts empty_context
end

(* The requalified constant is now available unqualified in the global context. *)
term empty_context

(* However, its definition is not. *)
thm empty_context_def (* ERROR *)

(* ... *)
end
```

In the above example, we enter an anonymous context block (`context begin ...
end`). Because this is not a named context, the effect of `requalify_consts` is
to requalify the given names into the global context, such that they become
accessible as unqualified names.

But we must first get hold of an existing name. We cannot use a qualified name,
because the name was presumably defined with `global_naming ARM` or similar, and
we cannot refer to `ARM` in a generic theory (because the generic theory also
has to work for `X64` and `RISCV64` etc). However, we can temporarily interpret
the Arch locale (`interpretation Arch .`) making *everything* in the Arch locale
available unqualified until the end of the context block. Indeed, in this case,
the only purpose of the anonymous context block is to limit the scope of this
`interpretation`.

Note: It is critical to the success of arch_split that we *never* interpret the
Arch locale, *except* inside an appropriate context block.

In a generic theory, we typically only interpret the Arch locale:

- to requalify names with no qualifier, or

- to keep existing proofs checking until we find time to factor out the
  architecture-dependent parts.

### Dealing with name clashes

Things are a bit more complicated when a generic theory needs to refer to an
architecture-specific thing, and there is already an architecture-generic thing
with the same unqualified name. That is, points 1 and 2 above hold, but 3 does
not. This happens frequently in the Haskell spec, where an architecture-generic
definition may refer to the corresponding architecture-specific definition. In
this case, we would like the unqualified name to refer to the generic concept,
and we would like to refer to the architecture-specific concept with an "Arch"
qualifier. To do this, we requalify the name into the Arch context:

- `l4v/spec/design/Retype_H.thy`

```isabelle
theory Retype_H
imports
  RetypeDecls_H
begin

term deriveCap (* Outside the Arch context, this is the arch-generic deriveCap function. *)

context Arch begin

(* Here, the global_naming scheme is "Arch" by default. *)

term deriveCap               (* In the Arch context, this is the deriveCap function for arch caps. *)
term RetypeDecls_H.deriveCap (* This is the arch-generic deriveCap function.                       *)

(* The following makes Arch.deriveCap refer to the architecture-specific constant. *)
requalify_consts deriveCap

(* Unfortunately, the above also means that in a context in which Arch is interpreted,
  `deriveCap` unqualified would refer to the arch-specific constant, which may break existing proofs.
   The following incantation ensures that `deriveCap` unqualified refers to the arch-generic constant,
   even when the Arch locale is interpreted. *)

context begin global_naming global
requalify_consts RetypeDecls_H.deriveCap
end

end

(* Now, in the global context... *)
term deriveCap        (* arch-generic             *)
term global.deriveCap (* arch-generic alternative *)
term Arch.deriveCap   (* arch-specific            *)

(* Also when we interpret the Arch locale... *)
context begin interpretation Arch .
term deriveCap        (* arch-generic             *)
term global.deriveCap (* arch-generic alternative *)
term Arch.deriveCap   (* arch-specific            *)
end

(* Even when we re-enter the Arch locale... *)
context Arch begin
term deriveCap        (* arch-generic             *)
term global.deriveCap (* arch-generic alternative *)
term Arch.deriveCap   (* arch-specific            *)
end

(* ... *)
end
```

In this case, we perform the requalification in the Arch context (`context Arch
begin ... end`). Contrast this with the previous case, where we entered an
anonymous context block, and interpreted the Arch locale.

There is a complication due to the way names from locales are bound into the
current context during interpretation. Without further intervention, an
interpretation of the Arch locale rebinds an unqualified name into the current
context, based on the last binding of that name within the locale. The result is
that the unqualified name now refers to same thing as the Arch-qualified name.
This is generally *not* what we want.

To fix this, we add a second requalification of the arch-generic constant
(obtained by a full theory-qualified reference). Since this is the last binding
of that name in the locale, it is used for rebinding the unqualified name during
interpretation. To avoid *also* overriding the binding of the Arch-qualified
name, we use a `global_naming` scheme *other than Arch* for this second
requalification, choosing `global` as our convention. A side effect is that the
arch-generic thing can be found with *either* an unqualified name or a
`global`-qualified name, whereas the arch-specific thing can only be found with
an `Arch`-qualified name.

Note: In a generic theory, we typically *only* enter the Arch context
to requalify names with the "Arch" qualifier.

### Name clashes between abstract and Haskell specs

In addition to name clashes between architecture-generic and
architecture-specific concepts, there are also many names in common between the
abstract and Haskell specs. Previously, these were disambiguated in the
refinement proofs by fully qualified references including theory names. For
architecture-specific things, the introduction of the Arch locale
(with global_naming) changed the required fully-qualified names, so many proofs
were broken. For example, `ArchRetype_H.updateCapData_def` became
`ArchRetype_H.ARM.updateCapData_def`.

Fixing this required search-and-replace, but rather than entrench the fragility
of theory-qualified references, we introduced different `global_naming` schemes
for abstract and Haskell specs: `ARM_A` for abstract specs, and `ARM_H` for
Haskell specs. We use `ARM` everywhere else. This means that the arch-specific
references only require either an `ARM_A` or `ARM_H` qualifier. No theory
qualifier is required, and the result is more robust to theory reorganisation.

In the future, when we are properly splitting the refinement proofs, we will may
want to extend this approach by introducing `Arch_A` and `Arch_H`
`global_naming` schemes to disambiguate overloaded requalified names.

### Name clashes with the C spec

There were also some clashes between Haskell and C specs. For names generated in
Kernel_C.thy, we simply added a Kernel_C qualifier. For names generated in
Substitute.thy, we used hand-crafted abbreviations, for example:

- `l4v/proof/crefine/Ipc_C.thy`

```isabelle
abbreviation "syscallMessageC ≡ kernel_all_substitute.syscallMessage"
lemmas syscallMessageC_def = kernel_all_substitute.syscallMessage_def
```

## Managing intra-theory dependencies

Initial work on splitting invariant definitions and proofs found that
within many theory files, there were both:

- architecture-specific definitions and proofs that depended on
  architecture-generic definitions and proofs, and

- vice-versa.

Since we use theory imports to separate architecture-specific concepts
from generic concepts, we found it was often necessary to split an
existing theory `Foo_AI` into *three* theories:

- `FooPre_AI` makes generic definitions that are needed for
  architecture-specific definitions.

- `$L4V_ARCH/ArchFoo_AI` imports `FooPre_AI`, and makes
  architecture-specific definitions and proofs in the `Arch` locale.

- `Foo_AI` imports `ArchFoo_AI`, and makes generic definitions and proofs
  that refer to architecture-specific constants and facts.

In some cases, `FooPre_AI` was not necessary, and it was sufficient to
have `Foo_AI` import `ArchFoo_AI`.

We see no reason to redo that previous work, so the above still
describes the current state of the abstract spec and some of the
invariants.

### Theory-specific architecture-generic locales

For further updates, however, we have developed a new pattern which we
hope will eliminate the need for more "Pre" theories, and only require
the addition of Arch theories for each existing theory.

In this pattern, an existing theory Foo_AI is split into two theories:

- `Foo_AI` retains the architecture-generic parts, using a locale `Foo_AI`
   where necessary to *assume* the existence of the appropriate
   architecture-specific parts.

- `$L4V_ARCH/ArchFoo_AI` imports `Foo_AI`, makes architecture-specific
  definitions and proofs in the `Arch` locale, and then interprets the
  `Foo_AI` locale globally.

After the locale `Foo_AI` is interpreted, we never speak of it again.

- `l4v/proof/invariant-abstract/Retype_AI.thy`

```isabelle
theory Retype_AI
imports VSpace_AI
begin

(* Here, we declare a theory-specific locale, which we will use
   to assume the existence of architecture-specific details. *)

locale Retype_AI

(* We can make architecture-generic definitions and lemmas here... *)

(* We have access to the clearMemoryVM constant, since
   it was previously requalified into the global context,
   but its definition is architecture-specific.
   Here, we assume a property that we need to continue
   making architecture-generic statements.
   Previously, this was a lemma that unfolded
   architecture-specific details. *)

context Retype_AI
extend_locale
  assumes clearMemoryVM_return [simp]:
  "clearMemoryVM a b = return ()"
end

(* ... *)

(* This lemma makes use of the assumption of the Retype_AI locale,
   so we prove it in the Retype_AI context. *)

lemma (in Retype_AI) swp_clearMemoryVM [simp]:
  "swp clearMemoryVM x = (λ_. return ())"
  by (rule ext, simp)

(* ... *)

end
```

- `l4v/proof/invariant-abstract/ARM/ArchRetype_AI.thy`

```isabelle
theory ArchRetype_AI
imports "../Retype_AI"
begin

context Arch begin global_naming ARM

(* We declare a collection of lemmas, initially empty,
   to which we'll add lemmas which will be needed to discharge
   the assumptions of the Retype_AI locale. *)

named_theorems Retype_AI_asms

(* We prove a lemma which matches an assumption of the Retype_AI locale,
   making use of an arch-specific definition.
   We declare the lemma as a memory of the Retype_AI_asms collection. *)

lemma clearMemoryVM_return[simp, Retype_AI_asms]:
  "clearMemoryVM a b = return ()"
  by (simp add: clearMemoryVM_def)

end

(* Having proved the Retype_AI locale assumptions, we can make a global
   interpretation of that locale, which has the effect of making all
   the lemmas proved from those assumptions available in the global context.
   The proof incantation is designed to give useful error messages if
   some locale assumptions have not been satisfied. For each theory,
   the same proof should be used, substituting only the names of the
   locale and the named_theorems collection. *)

global_interpretation Retype_AI?: Retype_AI
  proof goal_cases
  interpret Arch .
  case 1 show ?case by (intro_locales; (unfold_locales; fact Retype_AI_asms)?)
  qed

(* ... *)

end
```

Note that the custom command `extend_locale` allows us to pretend that
locales can be extended incrementally. This allows us to convert lemmas
to locale assumptions in-place, without having to move locale
assumptions to the point where the locale is initially declared.

## Qualify

Generally speaking, architecture-specific definitions and lemmas should
be put inside the `Arch` locale, with an appropriate `global_naming` scheme.

However, there are some commands that don't work in locales, for
example records. To work around this, we have a pair of custom commands:
`qualify` and `end_qualify`. Surrounding definitions with these commands has
the effect of adding the qualifier to the names of those definitions.

```isabelle
context ARM begin

typedecl my_type

end

qualify ARM

record foo = baz :: ARM.my_type -- "Qualifier still needed"

end_qualify

typ foo -- Error
term baz_update -- Free
thm foo.cases -- Error

typ ARM.foo
thm ARM.foo.cases
term ARM.baz_update

context ARM begin

typ foo
term baz_update
thm foo.cases

end
```

Some caveats:

- This only affects names. It does not do the usual context-hiding for simp (and
    other) declarations. There may be some post-hoc cleanup needed for removing
    these from the global theory in order to avoid inadvertently breaking
    abstraction.

- Interpreting the `Arch` locale won't bring unqualified versions of these names
    into the local scope.

In short: use sparingly and avoid when possible.

## HOWTO

For splitting new parts of the proof, this is roughly the workflow we follow:

Initially, we just want to populate Arch-specific theories with:

- types and constants whose definitions are clearly architecture-specific, for
  example if they refer to details of the page table structure;

- lemmas which we do not expect to be present on all architectures, in
  particular, those whose statements refer to architecture-specific constants;

- lemmas which are likely to exist on all architectures, but whose proofs
  probably can't be abstracted away from architecture-specific details.

Later, we can more work on actually creating abstractions that will
allow us to share more proofs across architectures, but for now this
means that we'll leave behind FIXMEs in generic theories for lemmas we
suspect can be abstracted, but currently have proofs that unfold
architecture-specific details.

The workflow:

- Pick a theory to work on. Co-ordinate using Jira if there are multiple people
  working on the split.

- Assuming you're starting for ARM, which has the most proofs: If there is no
  ARM-specific theory corresponding to this theory, create it in the ARM
  subdirectory, prefixing the name of the theory with "Arch".

  - The Arch theory should import the generic theory, and any theories which
    previously imported the generic theory should now import this Arch theory.

  - Fill out the template of the Arch theory, as per the section "Managing
    intra-theory dependencies" above.

- Look in the generic theory for a block of the form
  `context Arch begin (* FIXME: arch_split *) ... end`.

  - These indicate things that we've previously classified as belonging in an
    arch-specific theory.

  - Move the contents of that block to the Arch theory, within a
    block of the form `context Arch begin global_naming ARM ...
    end`.

- Look for subsequent breakage in the generic theory.

  - If this is in a subsequent Arch block (`context Arch begin (* FIXME:
    arch_split *) ... end`), just move that block.

  - Otherwise, if it's not obvious what to do, have a conversation with someone.
    We'll add more tips here as the process becomes clearer.

## Other Locales

Existing locales may need to be split up into architecture-generic and
architecture-specific variants. We can do this by making a second locale
which extends both the original locale and the Arch locale.

```isabelle
(* Before *)
locale my_locale = fixes x
begin
lemma non_arch_lemma: "Generic_statement"
lemma arch_lemma: "ARM_specific_statement"
end
(* After *)
locale my_locale = fixes x
locale Arch_my_locale = my_locale + Arch
```

To interpret these locales, we can just do a regular `interpretation`
for the arch-independent one. The arch-specific one, however, needs to
be interpreted **inside** the `Arch` locale. Contrary to intuition, this
is done using the `sublocale` command, not `interpretation`. This is
because the results of an `interpretation` are thrown away when the
locale context is exited.

```isabelle
theory Arch_Theory
context Arch_my_locale begin
lemma arch_lemma: "ARM_specific_statement"
end
end

theory Generic_Theory
context my_locale begin
lemma non_arch_lemma: "Generic_statement"
end
end
```

Often we want to lift some results out of our arch-specific locale into our
generic one (like an `unqualify`). This can be done using `interpretation`. Note
that because the effect of interpretation is temporary, we won't accidentally
pollute the global namespace with all of our architecture-specific content.

```isabelle
context Arch_my_locale begin

lemma quasi_arch_lemma[iff]: ....

end

context my_locale begin

interpretation Arch_my_locale by unfold_locales -- "Always by unfold_locales because they share the same base locale"

lemmas quasi_arch_lemma[iff] = quasi_arch_lemma -- "Similar to unqualify_facts, but keeps the result local to my_locale. Note that the attribute must be re-declared here (but will erroneously give a warning)"

end

interpretation my_locale "some_function" by unfold_locales ...

thm quasi_arch_lemma -- "Exported result"

thm arch_lemma -- "Error, still private"
```

## Breaking abstraction

It is important to note that this the namespacing convention is very much a
"soft" abstraction. At any point a proof author is free to open (or interpret)
the `Arch` locale and start writing architecture-specific proofs. This
intentionally allows proof authors to focus on one architecture at a time, and
not always have to think about the general case. However the expectation is that
this is eventually cleaned up so that the proofs for **all** architectures will
check.

To break into an arch-specific proof in the middle of a lemma, you can use the
following method:

```isabelle
subgoal proof - interpret Arch .

shows ?thesis \<Arch proof here\>

qed
```

This allows a proof author to write an arch-specific proof inside a generic
lemma. Note that the proof should check with all architectures otherwise this
doesn't really work.
