comptime {
    asm (
        \\.global _start
        \\_start:
        \\  li x10, 0
        \\  ecall
    );
}
