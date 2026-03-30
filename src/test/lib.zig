export fn inc(num: usize) usize {
    return num + 1;
}

export fn recur(num: usize) usize {
    if (num < 10) {
        return recur(num + 3);
    }
    return num;
}

fn popcount(x: usize) callconv(.c) usize {
    var n = x;
    var count: usize = 0;
    while (n != 0) {
        count += n & 1;
        n >>= 1;
    }
    return count;
}

export fn exercise(n: usize) usize {
    // Part 1: Fibonacci sequence (loops, ADD, branches)
    var a: usize = 0;
    var b: usize = 1;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const tmp = a +% b;
        a = b;
        b = tmp;
    }
    // a = fib(n)

    // Part 2: Collatz iteration (MUL via *%3, SRL via /2, branches, comparison)
    var val = a;
    var steps: usize = 0;
    while (val > 1 and steps < 200) {
        if (val & 1 == 0) {
            val >>= 1;
        } else {
            val = val *% 3 +% 1;
        }
        steps += 1;
    }

    // Part 3: Popcount via function call (JAL/JALR, loops, AND, SRL)
    const bits = popcount(a);

    // Part 4: Integer division and remainder (DIV, REM)
    const quot = a / (bits + 1);
    const rem = a % (steps + 1);

    // Part 5: Combine with shifts and bitwise ops (SLL, SRL, XOR, OR, AND)
    var result = steps;
    result ^= bits << 4;
    result +%= quot;
    result |= rem & 0xF;
    result = (result << 3) | (result >> 5);
    result &= 0x7FF;

    // Part 6: Signed comparison and arithmetic (SLT, SUB, SRAI)
    const signed: isize = @bitCast(result);
    const shifted = signed >> 2;
    if (shifted < @as(isize, @intCast(bits))) {
        result +%= bits;
    } else {
        result -%= bits;
    }

    return result;
}
