pub const Vec2 = struct {
    x: u32,
    y: u32,
};

pub fn sum_buff(buffer: []usize) usize {
    var sum: usize = 0;
    for (buffer) |value| {
        sum += value;
    }
    return sum;
}

pub fn shift_right(buffer: []u8, start: usize, end: usize, shift: usize) void {
    if (start >= end or shift == 0) return;

    var i: usize = end;
    while (i > start) {
        i -= 1;
        if (i + shift < buffer.len) {
            buffer[i + shift] = buffer[i];
        }
    }
}

pub fn shift_left(buffer: []u8, start: usize, end: usize, shift: usize) void {
    if (start >= end or shift == 0) return;

    var i: usize = start;
    while (i < end) {
        if (i + shift < buffer.len) {
            buffer[i] = buffer[i + shift];
        }
        i += 1;
    }
}
