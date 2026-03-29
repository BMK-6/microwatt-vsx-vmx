# Add MSR[VSX] bit and VSX unavailable interrupt infrastructure

- Status: accepted
- Date: 2026-03-16
- Files changed: common.vhdl, execute1.vhdl

## Context

Power ISA 3.1 defines MSR[VSX] at bit 23 (MSR bit position 63-40).
When MSR[VSX]=0, any VSX instruction must cause a VSX unavailable
interrupt (vector 0x800, same as FP unavailable). Without this bit:
- Software cannot enable/disable VSX at runtime
- Linux VSX context save/restore cannot function correctly
- MSR save/restore on interrupt entry/exit is incomplete

## Decision

### common.vhdl
Add MSR_VSX constant:
  constant MSR_VSX : integer := (63 - 40);

### execute1.vhdl — unavailable trap
Add VSX unavailable elsif branch after FP unavailable check.
Currently guarded with 'false' placeholder because no VSX instructions
exist in decode_types.vhdl yet.

When VSX opcodes are added to decode_types.vhdl, replace 'false' with:
  insn_code'pos(e_in.insn_type) >= insn_code'pos(INSN_first_vsx)

INSN_first_vsx constant already exists in decode_types.vhdl as a
marker — it points to INSN_xxlor, the first VSX opcode slot.

### execute1.vhdl — interrupt MSR clear
MSR_VSX is cleared on interrupt entry alongside MSR_FP:
  ctrl_tmp.msr(MSR_VSX) <= '0';

This matches Power ISA 3.1 interrupt handling requirements — VSX
state is not available in interrupt context until software explicitly
re-enables it via mtmsrd.

## Current temporary state

The VSX unavailable trap condition is 'false' — it never fires.
This is correct for now since no VSX instructions are decoded yet.
The infrastructure is in place for when decode is added.

## Consequences

- MSR[VSX] bit is now architecturally present and cleared on interrupt
- VSX unavailable trap fires correctly once VSX decode is added
- No functional change to current simulation — 'false' guard is a NOP
- Next step: revert ADR-001 write swap, then add VSX opcode decode
