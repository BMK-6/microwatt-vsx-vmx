# Split VSR register file into lo and hi 64-bit lanes

- Status: accepted
- Date: 2026-03-16
- Files changed: register_file.vhdl

## Context

Power ISA 3.1 defines 64 VSRs each 128 bits wide. VSR0-31 lower 64 bits
alias the FPRs. The existing FPU datapath is 64-bit wide so a single
128-bit array is impractical. The register file was restructured into
two independent 64-bit arrays:

- lo_registers[0:63][63:0] — FPR values and VSR lower halves
- hi_registers[0:63][63:0] — VSR upper halves (VSX extension)

fpu2.vhdl was added as a second FPU instance wired to the hi lane via
write_data_hi and write_enable_hi. However at this stage no VSX
instructions exist in the decode path, so the hi lane receives no real
instruction traffic. The lo lane (original fpu.vhdl) receives all
scalar FP instruction traffic normally.

## Problem

With no VSX opcodes decoded yet, there was no way to verify that fpu2
and the hi register lane were correctly connected end-to-end. The hi
lane path could be silently broken with no simulation evidence either way.

## Decision

Temporarily swap write_data and write_data_hi in register_file.vhdl
so that scalar FP instruction results flow through fpu2 and the hi lane
instead of the normal lo lane. This routes existing FP instruction
traffic through the new unverified path, making any wiring error
immediately visible in simulation.

This is a deliberate temporary test hack, not the correct architectural
state. The swap is not ISA-correct — FPR results must ultimately write
to lo_registers, not hi_registers.

## Consequences

### Positive
- Confirmed fpu2 and hi lane wiring is functionally correct under
  real instruction traffic without needing VSX opcode support first
- Visible simulation failure would occur if hi lane had a wiring bug

### Negative
- Current register_file.vhdl is NOT architecturally correct
- FPR writes are going to hi_registers instead of lo_registers
- Must be reverted before VSX decode integration begins
- Any simulation results in the current state reflect hi-lane behaviour
  only — lo-lane results are not being exercised by FP instructions

## Next action required

Revert write_data and write_data_hi to their correct assignments before
implementing VSX opcode decode in decode1.vhdl. At that point real VSX
instruction traffic will drive the hi lane correctly.
