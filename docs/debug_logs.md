# Debug Logs – Microwatt Vector Unit Integration

## [2026-02-21] Instruction Decode Analysis
- Observed mixed GPR/FPR control flow
- Hard to classify instruction domains
- No functional change made yet

## Notes
- core_tb used for simulation
- Logging redirected for focused analysis

## [2026-02-22] Instruction Intent Separation – Validation
- Introduced explicit instruction intent signal: `is_insn_float`
- Derived `is_insn_float` in `decode1` using `INSN_first_frs` boundary
- Propagated intent signal to register file via decode interface
- Added sanity assertion in `register_file`:
  - Non-FP instruction must not access FPR space
  - Assertion checks only enabled operands
- Ran full `core_tb` simulation
- No warnings observed
- Confirms decode intent matches existing register access behavior
-Vector Intent Hook Added
## [2026-02-22] FP Baseline Validation
- Executed default Microwatt FPU test suite
- Verified FP load/store, ALU, and FPSCR instructions
- Confirmed FP exception handling via MSR[FP]
- No failures observed
- Scalar FP deemed architecturally stable for VSX layering

---

## Notes
- `core_tb` used for functional and architectural validation
- Simulation output redirected to log file for focused analysis
- Added `is_insn_vector` signal to decode and regfile interface
- Signal remains inactive (`0`) in current phase
- No functional behavior changes introduced in this phase
