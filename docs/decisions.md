# Design Decisions – Microwatt Vector Unit Integration

## Decision 1: VSX-First Strategy
**Date:** 2026-02-21

**Decision:**
Implement VSX before VMX.

**Reasoning:**
- VSX required for float128
- Reuse of existing FPU hardware
- Lower RTL complexity

**Alternatives Considered:**
- VMX-first (rejected due to complexity)

---

## Decision 2: Instruction Domain Separation
**Date:** 2026-02-21

**Decision:**
Logically separate GPR and FPR instruction paths.

**Reasoning:**
- Required for clean VSX integration
- Aligns with ISA structure
- Minimal functional impact


## Decision 3: Incremental VSX Introduction Using Partial VSR Model
**Date:** 2026-02-22

**Decision**

VSX support will be introduced incrementally using a partial Vector-Scalar
Register (VSR) model, reusing existing floating-point register storage.

**Details**

- Initial VSX instructions operate only on the lower 64 bits of VSR[0-31]
- Existing FPRs serve as the lower half of VSRs
- No 128-bit register file or vector execution unit is added initially
- Upper 64 bits of VSRs and VSR[32-63] are deferred to later phases

**Rationale**

- VSX instructions are architecturally layered on floating-point semantics
- Reusing FPU and FPR infrastructure minimizes risk and complexity
- Enables early validation of VSX decode and control flow
- Avoids large RTL refactors before VSX behavior is understood

**Consequences**

- Initial VSX behavior is limited to scalar-width execution
- Full 128-bit VSR support will require future architectural extensions


## Decision 4: Select `xxlor` as the First VSX Instruction
**Date:** 2026-02-23

**Decision**  
Use the VSX instruction `xxlor` as the first instruction for VSX bring-up.

**Rationale**
- `xxlor` is a pure logical operation with no numerical complexity
- No rounding, exceptions, or FPSCR side effects
- Allows validation of:
  - VSX decode
  - VSR operand mapping
  - Register overlap between FPRs and VSRs
- Can be implemented using existing 64-bit datapaths
- Ideal for validating control-path correctness before widening datapaths

**Consequences**
- Initial `xxlor` implementation operates on the lower 64 bits of VSR operands only
- Upper 64 bits are treated as architecturally unimplemented
- Confirms VSX control and decode correctness prior to full vector support

