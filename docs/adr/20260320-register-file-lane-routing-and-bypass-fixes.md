# Register file lane routing and bypass fixes for TEST_FPU2_PATH

- Status: accepted
- Date: 2026-03-20
- Files changed: register_file.vhdl, core.vhdl, execute1.vhdl, writeback.vhdl

## Context

The split lo/hi register file (see ADR split-vsr-register-file) routes
FPR results through write_data_hi to lo_registers when TEST_FPU2_PATH=
true. Four independent bugs caused this path to silently fail:

1. core.vhdl had TEST_FPU2_PATH => false for register_file_0
2. execute1.vhdl wired fv2 operands to uninitialized hi-lane signals
3. register_file.vhdl forwarding logic did not match the write swap
4. writeback bypass carried write_data=0 instead of write_data_hi

Each bug was independently sufficient to break the entire FPR data path.
Together they meant fpu2 computed correct results but they never reached
the register file, and reads always returned 0 or stale values.

## Decisions

### 1. core.vhdl: register_file TEST_FPU2_PATH must match pipeline

register_file_0 instantiation had:
  TEST_FPU2_PATH => false

This made the register file use the normal path (write_data → lo_registers)
while writeback was sending results to write_data_hi. The result was:
- write_data_hi (containing the fpu2 result) → hi_registers (discarded)
- write_data (= 0) → lo_registers
- All FPR reads returned 0

Fix: TEST_FPU2_PATH => true in register_file_0 generic map in core.vhdl.

### 2. execute1.vhdl: fv2 operands use lo-lane data in TEST_FPU2_PATH

fv2.fra/frb/frc were wired to a_in_hi/b_in_hi/c_in_hi for future VSX
upper-half operands. For scalar FP instructions these signals are
uninitialized (the register file returns zeros for the hi lane when
reading GPR/FPR operands that have no hi data).

With garbage operands, fpu2 was computing results from uninitialized
data. For some operations this triggered NaN/invalid exceptions which
set FPSCR sticky bits, causing fp_exception_next to fire on subsequent
instructions.

Fix in execute1.vhdl:
  if TEST_FPU2_PATH then
      fv2.fra := a_in;   -- lo-lane operands (known-good for scalar FP)
      fv2.frb := b_in;
      fv2.frc := c_in;
  else
      fv2.fra := a_in_hi;  -- VSX upper-half operands
      fv2.frb := b_in_hi;
      fv2.frc := c_in_hi;
  end if;

### 3. register_file.vhdl: forwarding mirrors write-path swap

The write path with TEST_FPU2_PATH=true:
  lo_registers(fr_addr) <= w_in.write_data_hi   -- fpu2 result
  hi_registers(fr_addr) <= w_in.write_data       -- (zero in scalar path)

The forwarding path must produce the same mapping. When a write and
a read to the same FPR happen in adjacent cycles, the forwarding
combinational process must return write_data_hi as out_data_1 (lo lane)
so that a_in receives the correct value.

Original forwarding (incorrect for TEST_FPU2_PATH):
  out_data_1    := prev_write_data      -- was: fpu2 result
  out_data_1_hi := prev_write_data_hi   -- was: 0

Fixed forwarding:
  if TEST_FPU2_PATH and addr_1_reg(6) = '1' then
      out_data_1    := prev_write_data_hi  -- fpu2 result (from write_data_hi)
      out_data_1_hi := prev_write_data     -- 0
  else
      out_data_1    := prev_write_data
      out_data_1_hi := prev_write_data_hi
  end if;

Same fix applied to all three read ports (out_data_1/2/3).

### 4. writeback.vhdl: bypass carries write_data_hi for FPR writes

wb_bypass.data was always w_out.write_data. For fpu2 writes,
w_out.write_data = 0 and the actual result is in w_out.write_data_hi.
Decode2 uses wb_bypass.data for all three operand ports (A, B, C).
Any instruction reading an FPR written by fpu2 within the bypass window
received 0.

This affected back-to-back FP instructions (fmr followed immediately
by stfd, mffs followed immediately by stfd, etc.).

Fix: wb_bypass.data = write_data_hi when FPR write in TEST_FPU2_PATH:
  if HAS_FPU and TEST_FPU2_PATH and w_out.write_reg(6) = '1' then
      wb_bypass.data <= w_out.write_data_hi;
  else
      wb_bypass.data <= w_out.write_data;
  end if;

Note: the bypass has no data_hi field. For TEST_FPU2_PATH, all FPR
results are in the lo lane (write_data_hi → lo_registers). The bypass
therefore only needs to carry the lo-lane value. For full VSX where
some instructions write both lanes, decode2 bypass extension and
a data_hi field in bypass_data_t will be required.

## FP load path (lfs, lfd, lfiwax, lfiwzx)

FP loads go through loadstore1, not fpu2. Writeback receives the result
via l_in, not fp_in2. The existing writeback path sets:
  w_out.write_data    = l_in.write_data
  w_out.write_data_hi = l_in.write_data  (when TEST_FPU2_PATH and FPR)

So both lanes receive the loaded value. register_file writes:
  lo_registers(fr_addr) = write_data_hi = loaded value   ✓
  hi_registers(fr_addr) = write_data    = loaded value   (redundant)

This is correct. The bypass also returns write_data_hi = loaded value
for the back-to-back stfd/stfs case.

## DP→SP store path (stfs, stfiwx)

stfs and stfiwx read the FPR via the B or C port (loadstore data).
b_in = e_in.read_data2 = register file read2_data = lo_registers[FPR].
With the fixes above, lo_registers contains the correct FPR value.
The loadstore unit then performs DP→SP conversion internally.

## Consequences

- All four bugs were independently necessary for correct operation
- With fixes, all FPR read/write/forward/bypass paths are consistent
  with the TEST_FPU2_PATH lo-lane routing through write_data_hi
- When TEST_FPU2_PATH is reverted: remove the bypass fix, the forwarding
  swap, and the fv2 operand fix. The write-path swap in register_file.vhdl
  was already the subject of a separate ADR (split-vsr-register-file)
  and will be handled there
