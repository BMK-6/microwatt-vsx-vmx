# Architecture Notes - Microwatt Vector Unit Integration

## Microwatt Overview
- In-order PowerISA core
- Supports integer and scalar floating-point execution
- Linux-capable design

## Current Instruction Classification in Microwatt
date :21 feb 2026

Microwatt already separates General-Purpose Instructions (GPI) and
Floating-Point Instructions (FPI) at the decode level.

This separation is achieved through the ordering of the `insn_code`
enumeration and the use of boundary constants such as:

- `INSN_first_frs`
- `INSN_first_frab`
- `INSN_first_frabc`

Because `insn_code` is an ordered enumerated type, floating-point
instructions are placed after a specific boundary (`INSN_first_frs`).
This allows classification using range comparison:

    if icode >= INSN_first_frs then
        -- floating-point instruction
    end if;

Therefore, at the ISA and decode level, Microwatt already
distinguishes between integer and floating-point instructions.



## Current Instruction Flow
date :21 feb 2026

Although instruction classification is separate, Microwatt uses a
single physical register file to store both GPRs and FPRs.

The register file contains 64 entries:
- Entries 0-31  → GPRs
- Entries 32-63 → FPRs

The distinction between GPR and FPR is encoded in the MSB of the
6-bit register index (`gspr_index_t`).

Thus:

- Instruction domain is implicit in the register address MSB
- Execution paths share forwarding, debug, and writeback logic

This means that separation exists architecturally, but not yet
as an explicit control-domain abstraction.

## Identified Limitation
date :21 feb 2026


Current Microwatt behavior:

Instruction Type  → Determined in decode  
Register Selection → Inferred from register address MSB  
Execution Control  → Partially shared  

This creates implicit coupling between instruction domain and
register addressing.

For future VSX integration, instruction intent must become explicit
(`is_insn_float`, `is_insn_vector`) rather than being inferred solely
from register index encoding.


## Planned Direction
date :21 feb 2026

- Introduce explicit instruction intent signals to separate
  general-purpose and floating-point instruction domains
- Derive `is_insn_float` in `decode1` using the ISA boundary
  `INSN_first_frs`
- Preserve existing register addressing and execution behavior
  during initial separation
- Use explicit instruction intent as the foundation for future
  VSX instruction integration

date :22 feb 2026

-Instruction intent hierarchy includes is_insn_float and is_insn_vector, with vector intent inactive until VSX integration.

VSX Register Model (Architectural)

- VSX introduces 128-bit Vector-Scalar Registers (VSRs)
- Microwatt currently implements only 64-bit storage
- Proposed initial mapping:
  - VSR[0-31].lower 64 bits map to existing FPRs
  - VSR[0-31].upper 64 bits are reserved
  - VSR[32-63] not implemented in initial phase
- Scalar FP instructions operate on the lower half of VSRs
- VSX instructions will reuse FPU execution where applicable

