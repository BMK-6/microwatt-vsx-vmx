# Exception handling integration for dual-FPU pipeline

- Status: in-progress
- Date: 2026-03-20
- Files changed: writeback.vhdl, execute1.vhdl, common.vhdl, core.vhdl

## Context

Microwatt's exception and interrupt infrastructure was designed for a
single FPU. Adding fpu2 as a parallel unit requires all exception paths
to handle two independent FPU result sources simultaneously:

- FP program interrupt (do_intr from FPSCR[FEX] with fe_mode≠00)
- FP unavailable interrupt (MSR[FP]=0 when FP instruction arrives)
- fp_exception_next (deferred FP interrupt from MSR[FE0:FE1] change)
- Pipeline stall/flush on interrupt
- CR1 update (rc=1 on FP arithmetic instructions)
- FPSCR update (mtfsf, mtfsfi, mtfsb0, mtfsb1, mcrfs)
- XER carry update (integer division through FPU)
- Writeback bypass for FPR results

The original single-FPU path assumed fp_in is the only FPU result
source. Every one of these paths required extension for fp_in2.

## Decisions

### 1. complete_out fires on interrupt as well as valid completion

Problem: fpu2 sets r.complete='0' and r.do_intr='1' when firing an
FP program interrupt. fp_in2.valid='0' so complete_out never asserted.
The instruction tag was never retired. The pipeline stalled permanently.

Fix in writeback.vhdl: complete_out now fires when .interrupt='1' OR
.valid='1' for all four result sources (e_in, l_in, fp_in, fp_in2).

### 2. Synchronous exceptions bypass fpu2 busy gate

Problem: execute1 gated all exception delivery on:
  (ex1.busy or l_in.busy or fp_in.busy or fp_in2.busy) = '0'
With TEST_FPU2_PATH=true, fpu2 is busy whenever an FP instruction is
executing. FP unavailable (MSR[FP]=0) is a synchronous precise
exception caused by the current instruction and independent of any
prior in-flight instruction in fpu2. When fpu2 was busy, FP unavailable
was silently suppressed and the faulting instruction executed normally.

Fix in execute1.vhdl: added elsif branch:
  elsif valid_in = '1' and actions.exception = '1' then
      v.e.interrupt := '1';
actions.exception covers only synchronous decode-time exceptions
(FP unavailable, illegal, privileged, misaligned). Async interrupts
(irq_valid path) remain correctly gated on the busy condition.

### 3. CR writes use per-unit mask

Problem: writeback used fp_in.write_cr_mask for both fp_in and fp_in2.
With TEST_FPU2_PATH=true, fp_in.write_cr_mask is always zero (fpu1
never fires). Every CR write from fpu2 silently wrote nothing.
fcmpu results were lost. rc=1 CR1 updates were lost.

Fix in writeback.vhdl: separated into independent if-blocks:
  if fp_in.write_cr_enable = '1' then ... use fp_in mask/data
  if fp_in2.write_cr_enable = '1' then ... use fp_in2 mask/data

This follows the IBM dual-FPU convention: each unit owns its mask.
The scheduler enforces no simultaneous CR writes (structural hazard).

### 4. Writeback bypass carries write_data_hi for FPR results

Problem: wb_bypass.data = w_out.write_data = 0 for fpu2 results.
fpu2 places its result in write_data_hi (routed to lo_registers via
TEST_FPU2_PATH swap). Any instruction reading a register written by
fpu2 within the bypass window received 0.

Fix in writeback.vhdl:
  if HAS_FPU and TEST_FPU2_PATH and w_out.write_reg(6) = '1' then
      wb_bypass.data <= w_out.write_data_hi;
  else
      wb_bypass.data <= w_out.write_data;
  end if;

### 5. Consistency assertions extended to four sources

The clocked writeback assertions originally checked only e_in, l_in,
fp_in for mutual exclusion. fp_in2 was unchecked — simultaneous writes
from multiple sources could corrupt register state silently.

Assertions now cover:
- valid: (e_in + l_in + fp_in) ≤ 1 and (e_in + l_in + fp_in2) ≤ 1
- write_enable: four-way mutual exclusion for lo lane; fp_in2
  write_enable_hi permitted alongside fp_in (same VSX reg, dual lane)
- write_cr_enable: four-way sum ≤ 1
- write_xerc: three pairwise conflict checks

### 6. intr_seg gated on e_in.interrupt

Problem: intr_seg = e_in.alt_intr & e_in.alt_intr was set
unconditionally. For FP program interrupts sourced from fp_in2, a
stale e_in.alt_intr could corrupt the interrupt vector calculation.

Fix in writeback.vhdl:
  if e_in.interrupt = '1' then
      intr_seg := e_in.alt_intr & e_in.alt_intr;
  else
      intr_seg := "00";  -- FP/FPU2 interrupts always use normal space
  end if;

### 7. fp_complete uses OR not AND

events.fp_complete was: fp_in.valid and fp_in2.valid (always 0 in
TEST_FPU2_PATH since fpu1 never fires).
Fixed to: fp_in.valid or fp_in2.valid.

### 8. XER routing: per-unit if-blocks with fpu2 priority

XER carry updates from fpu2 (integer division) were handled with an
if-elsif chain where fp_in could overwrite fp_in2. Fixed to independent
if-blocks where fp_in2 has priority as the active unit in TEST_FPU2_PATH.

## FPSCR coherence across two FPUs

fpu1 and fpu2 each maintain independent r.fpscr state. In
TEST_FPU2_PATH, all FP instructions (including mtfsf, mffs, mtfsfi)
go to fpu2. fpu1's r.fpscr stays at reset value 0.

When the pipeline flushes:
- fpu2 with r.do_intr='1': FPSCR preserved (interrupt caused it)
- fpu2 with r.do_intr='0': FPSCR rolled back to r.comm_fpscr

This is correct for the TEST_FPU2_PATH single-unit case. When full
VSX is integrated and mtfsf routes to fpu1 while VSX arithmetic routes
to fpu2, the two FPSCRs will diverge. A coherence mechanism will be
required at that point. Deferred.

## Test results

22 of 27 fpu.c tests pass after these changes.
5 remaining failures under investigation (see ADR fpu2-fork).

## Consequences

- Exception infrastructure is complete for single-active-FPU case
- Full dual-issue VSX will require scheduler enforcement of CR/XER
  structural hazards and FPSCR coherence — both deferred
- TEST_FPU2_PATH=true must be reverted before VSX decode integration
