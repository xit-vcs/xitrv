export fn inc(num: usize) usize {
    return num + 1;
}

export fn recur(num: usize) usize {
    if (num < 10) {
        return recur(num + 3);
    }
    return num;
}
