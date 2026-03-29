# VSX-first implementation, VMX integer vector deferred

- Status: accepted
- Date: 2026-03-16
- Files changed: README_vec.md

## Context

Power ISA 3.1 defines both VSX (Vector-Scalar Extension, FP-centric)
and VMX (AltiVec, integer vector). Microwatt currently lacks both.
Modern GCC and glibc require VSX for float128 and vectorised FP
operations. Without VSX support in hardware, the toolchain falls back
to software emulation which is architecturally incorrect for a core
claiming Power ISA 3.1 compliance.

## Decision

Implement VSX scalar FP support first. VMX integer vector support
is explicitly deferred to a later phase.

Priority order:
1. VSX scalar FP (xsadddp, xsmuldp, xsdivdp, xssqrtdp)
2. VSX vector FP (xvadddp, xvmuldp)
3. VMX integer vector — deferred

## Reasons for VSX-first

- GCC and glibc float128 requirement is addressable with VSX alone
- VSX scalar FP reuses the existing FPU datapath directly
- VMX integer ops require 4x32-bit lane logic not present in the
  current FPU — larger scope, different datapath
- Smaller initial scope reduces integration risk

## VMX load/store (lvx, stvx)

lvx and stvx can be implemented using the existing lq/stq hardware
path which already handles 128-bit memory access as multicycle
operations. These are therefore not blocked on new memory hardware —
only on instruction decode and multicycle sequencing logic.

This makes lvx/stvx lower risk than VMX integer ops and they may be
implementable earlier than the rest of VMX.

## Consequences

- Toolchain float128 and vectorised FP unblocked by VSX alone
- VMX integer vector support requires separate future effort
- lvx/stvx feasible via existing lq/stq multicycle path when needed
