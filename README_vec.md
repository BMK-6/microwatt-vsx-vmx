# Microwatt Vector Unit Integration

## Project Overview
This project aims to extend the Microwatt open-source PowerISA core by adding
vector execution support aligned with Power ISA 3.1. The focus is on integrating
VSX (Vector-Scalar Extension) functionality in a way that is architecturally
correct, minimal, and reusable with existing Microwatt hardware.

---

## Goal
- Achieve A2O-style architectural compliance with Power ISA 3.1
- Add support for VSX (and later VMX) instructions
- Reuse existing Microwatt FPU hardware wherever possible
- Validate vector instruction integration using Microwatt simulation (core_tb)

---

## Why This Goal
Microwatt is supported by mainline Linux; however, it lacks VMX/VSX support.
Modern toolchains (GCC, glibc) require VSX for features such as float128.
Currently, software workarounds are used to bypass this limitation.
This project aims to address the issue architecturally by extending the core
itself rather than relying on software patches.

---

## Scope
### In Scope
- VSX instruction support (minimal functional subset)
- Architectural register modeling (VSR/FPR relationship)
- Instruction decode and execution path separation
- Simulation-based verification

### Out of Scope (for now)
- Full VMX integer vector support
- High-performance SIMD pipelines
- Out-of-order execution
- Throughput optimization

---

## Architecture Direction
- VSX-first approach (VMX later)
- Logical separation of:
  - General-purpose instructions (GPR)
  - Floating-point instructions (FPR)
  - Vector instructions (VSX)
- Reuse of existing FPU execution units
- Multi-cycle execution acceptable
- ISA correctness prioritized over performance

---

## Current Focus
- Separating instruction paths for:
  - General-purpose integer instructions
  - Floating-point instructions
- Identifying and isolating target register banks
- Preparing decode logic for future VSX integration

---


