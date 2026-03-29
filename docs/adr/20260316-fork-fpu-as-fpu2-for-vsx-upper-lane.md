# Fork fpu.vhdl as fpu2.vhdl for VSX upper lane writeback

- Status: accepted
- Date: 2026-03-16
- Files changed: fpu2.vhdl (new)

## Context

VSX requires a second FPU instance that writes results to the VSR hi
lane (write_data_hi, write_enable_hi) rather than the lo lane used by
the original scalar FP path. The full FPU datapath (add, mul, div,
sqrt, fmadd, rounding, FPSCR, exceptions) is identical — only the
output lane differs.

## Decision

Fork fpu.vhdl into fpu2.vhdl with architecture name vsx_upper.
Minimal changes from the original:
- Entity name: fpu2
- Architecture name: vsx_upper
- write_enable  → write_enable_hi
- write_data    → write_data_hi

All internal computation logic is identical to fpu.vhdl.

## Integration status (updated 2026-03)

### Working (verified through fpu.c test suite, 22 of 27 passing)
- fadd, fsub, fmul, fdiv, fmadd, fnmadd, fmsub, fnmsub
- frsp, fcfid, fcfidu, fcfids, fcfidus
- fctid, fctidu, fctidz, fctiduz, fctiw, fctiwz, fctiwu, fctiwuz
- fabs, fnabs, fneg, fmr, fcpsgn, fmrgew, fmrgow
- frin, friz, frip, frim
- fsqrt, fsqrts, frsqrte, fre
- fcmpu, fcmpo, ftdiv, ftsqrt
- mffs and all mffs variants (mffsce, mffscrn, mffscrni, mffsl)
- mtfsf, mtfsfi, mtfsb0, mtfsb1, mcrfs
- FP unavailable interrupt (MSR[FP]=0 → vector 0x800)
- FP program interrupt via fp_exception_next (MSR[FE0:FE1] change)
- FP program interrupt via do_intr (enabled exception in fpu2)
- CR1 update path (rc=1 on FP arithmetic)
- CR field write from fcmpu/fcmpo
- XER carry update from integer-in-FPU operations
- Load/store FP (lfd, stfd, lfs, stfs, lfiwax, lfiwzx, stfiwx)
- Integer division through FPU (divd, divdu, divde, divdeu, modsd, modud)

### Under investigation (5 of 27 failing)
- fpu_test_3:  lfs/stfd SP→DP and lfd/stfs DP→SP round-trip
- fpu_test_9:  fctid/fctidu with round-to-nearest
- fpu_test_11: frin/friz/frip/frim round-to-integer
- fpu_test_20: fcmpu CR result
- fpu_test_21: frsqrte result at i=1
- fpu_test_22: fsqrt result at i=1

All five remaining failures appear to share a common symptom:
get_fpscr() returns 0 when FPSCR should be non-zero, and/or CR
is not written. Root cause under investigation — likely a timing
interaction between mffs result writeback and immediate stfd read.

## Key bug fixes applied during integration

### FP forwarding data swapped (register_file.vhdl)
With TEST_FPU2_PATH=true, prev_write_data latching must mirror the
write-path swap. Fixed by applying the same swap condition to the
forwarding registers.

### Synchronous exception delivery blocked by fp_in2.busy (execute1.vhdl)
FP unavailable, illegal, and privileged exceptions were silently
suppressed when fpu2 was busy executing a previous instruction.
Fixed: added elsif exception='1' branch that delivers synchronous
precise exceptions immediately regardless of fpu2 busy state.

### complete_out never fired on FP program interrupt (writeback.vhdl)
When fpu2 fired do_intr='1', r.complete='0' so fp_in2.valid='0'.
complete_out was never asserted. The instruction tag was never retired.
The pipeline stalled permanently.
Fixed: complete_out now fires on .interrupt='1' as well as .valid='1'.

### CR writes from fpu2 used zero mask (writeback.vhdl)
When fp_in2.write_cr_enable='1', c_out.write_cr_mask was taken from
fp_in.write_cr_mask which is always zero (fpu1 never fires in
TEST_FPU2_PATH). Every CR write from fpu2 silently wrote nothing.
Fixed: separate if-blocks per unit, each using its own write_cr_mask.

### wb_bypass.data=0 for all fpu2 FPR writes (writeback.vhdl)
fpu2 places its result in write_data_hi, not write_data. The writeback
bypass carried write_data=0. Any instruction that read a register
written by fpu2 within the bypass window received 0.
Fixed: wb_bypass.data returns write_data_hi for FPR writes when
TEST_FPU2_PATH=true and write_reg(6)='1'.

### Register file TEST_FPU2_PATH mismatch (core.vhdl)
register_file_0 instantiation had TEST_FPU2_PATH => false while
execute1 and writeback had it true. fpu2 results went to hi_registers
but reads came from lo_registers, returning stale/zero values for
all FP operations.
Fixed: TEST_FPU2_PATH => true in register_file_0 generic map.

### fv2 operands wired to uninitialized hi lane (execute1.vhdl)
With TEST_FPU2_PATH=true, fv2.fra/frb/frc were wired to
a_in_hi/b_in_hi/c_in_hi which were uninitialized for scalar FP
instructions. fpu2 received garbage operand values.
Fixed: in TEST_FPU2_PATH mode, fv2.fra/frb/frc = a_in/b_in/c_in
(the lo-lane operands with known-good values).

## Consequences

- fpu2.vhdl is a fork — shared logic changes must be mirrored manually
- Long term: refactor into single parameterised entity (lo/hi generic)
- TEST_FPU2_PATH must be reverted to false before VSX decode integration
- See also: ADR split-vsr-register-file for register lane architecture
