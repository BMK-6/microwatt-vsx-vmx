typedef unsigned long long u64;

volatile u64 a_mem = 0x1122334455667788ULL;
volatile u64 b_mem = 0xFFFF0000FFFF0000ULL;
volatile u64 result_mem = 0;

int main(void)
{
    u64 expected = a_mem | b_mem;

    __asm__ volatile(
        "lfd 0, %[a]\n\t"        // load FPR0
        "lfd 1, %[b]\n\t"        // load FPR1
        "xxlor 2, 0, 1\n\t"      // FPR2 = FPR0 | FPR1
        "stfd 2, %[res]\n\t"     // store FPR2
        :
        : [a] "m" (a_mem),
          [b] "m" (b_mem),
          [res] "m" (result_mem)
        : "memory"
    );

    if (result_mem != expected)
        return 1;

    return 0;
}
