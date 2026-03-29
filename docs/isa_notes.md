# ISA Notes – Microwatt Vector Unit Integration

## Reference
- Power ISA Version 3.1

## VSX Overview
- VSX introduces 128-bit Vector-Scalar Registers (VSRs)
- VSRs overlap with FPRs for scalar floating-point operations
- Vector operations operate on full 128-bit registers

## VMX vs VSX
- VMX: Integer vector operations (deferred)
- VSX: Floating-point scalar and vector operations

## Register Model
- GPR: Integer registers
- FPR: 64-bit floating-point registers
- VSR: 128-bit architectural registers

## Notes
- VSX is required for float128 support in modern toolchains
- Architectural correctness prioritized over performance

22-02-2026

## VSX Introduction Scope (Initial Phase)

Power ISA 3.1 defines Vector-Scalar Registers (VSRs) as 128-bit architectural
registers used by VSX instructions.

In Microwatt Vector Unit Integration, VSX support is introduced incrementally.
The initial phase implements a *partial VSR model* aligned with the ISA, but
without full 128-bit physical storage.

### Initial VSR Model

- VSRs are treated as architectural entities
- Only VSR[0–31] are accessible in the initial phase
- Lower 64 bits of VSR[0–31] map directly to existing FPR[0–31]
- Upper 64 bits of VSR[0–31] are reserved and not implemented
- VSR[32–63] (vector-only registers) are not implemented in the initial phase

### VSX Instruction Semantics (Initial Phase)

- VSX instructions operate only on the lower 64 bits of VSR operands
- Upper 64 bits are treated as architecturally unimplemented
- No vector register file or 128-bit datapath is added in the initial phase
- This behavior is documented and intentional

This phased approach preserves ISA correctness while minimizing disruption
to the existing Microwatt design.
