const std = @import("std");

const ProgramHeader = struct {
    kind: union(enum) {
        unused,
        load,
        dynamic,
        interp,
        note,
        shlib,
        phdr,
        tls,
        os: u32,
        proc: u32,
    },
    permissions: packed struct {
        executable: bool,
        writeable: bool,
        readable: bool,
    },
    offset: u64,
    virtual_addr: u64,
    physical_addr: u64,
    file_size: u64,
    memory_size: u64,
    alignment: u64,
};

pub fn parseElf(allocator: std.mem.Allocator, reader: anytype) !void {
    // elf header

    const magic_bytes = try reader.readBytesNoEof(4);
    if (!std.mem.eql(u8, &magic_bytes, &[_]u8{ 0x7f, 0x45, 0x4c, 0x46 })) {
        return error.InvalidMagic;
    }

    switch (try reader.readByte()) {
        0x01 => return error.UnsupportedClass, // 32 bit
        0x02 => {}, // 64 bit
        else => return error.InvalidClass,
    }

    const endian: std.builtin.Endian = switch (try reader.readByte()) {
        0x01 => .little,
        0x02 => .big,
        else => return error.InvalidEndian,
    };

    switch (try reader.readByte()) {
        0x01 => {},
        else => return error.UnsupportedElfVersion,
    }

    switch (try reader.readByte()) {
        0x00 => {}, // system v
        else => return error.UnsupportedAbi,
    }

    switch (try reader.readByte()) {
        0x00 => {},
        else => return error.UnsupportedAbiVersion,
    }

    _ = try reader.readBytesNoEof(7); // padding

    switch (try reader.readInt(u16, endian)) {
        0x03 => {}, // shared
        else => return error.UnsupportedFileType,
    }

    switch (try reader.readInt(u16, endian)) {
        0xF3 => {}, // risc v
        else => return error.UnsupportedIsa,
    }

    switch (try reader.readInt(u32, endian)) {
        0x01 => {},
        else => return error.UnsupportedVersion,
    }

    _ = try reader.readInt(u64, endian); // entry

    switch (try reader.readInt(u64, endian)) {
        64 => {},
        else => return error.UnsupportedProgramHeaderTableOffset,
    }

    _ = try reader.readInt(u64, endian); // shoff
    _ = try reader.readInt(u32, endian); // flags

    switch (try reader.readInt(u16, endian)) {
        64 => {},
        else => return error.UnsupportedHeaderSize,
    }

    switch (try reader.readInt(u16, endian)) {
        0x38 => {},
        else => return error.UnsupportedProgramHeaderTableEntrySize,
    }

    const phnum = try reader.readInt(u16, endian);
    if (phnum > 32) {
        return error.TooManyProgramHeaderTableEntries;
    }

    switch (try reader.readInt(u16, endian)) {
        0x40 => {},
        else => return error.UnsupportedSectionHeaderTableEntrySize,
    }

    _ = try reader.readInt(u16, endian); // shnum
    _ = try reader.readInt(u16, endian); // shstrndx

    // program headers

    var program_headers = std.ArrayList(ProgramHeader).init(allocator);
    defer program_headers.deinit();
    for (0..phnum) |_| {
        const kind = try reader.readInt(u32, endian);
        const permissions = try reader.readInt(u32, endian);
        const header = ProgramHeader{
            .kind = switch (kind) {
                0x00000000 => .unused,
                0x00000001 => .load,
                0x00000002 => .dynamic,
                0x00000003 => .interp,
                0x00000004 => .note,
                0x00000005 => .shlib,
                0x00000006 => .phdr,
                0x00000007 => .tls,
                0x60000000...0x6FFFFFFF => .{ .os = kind },
                0x70000000...0x7FFFFFFF => .{ .proc = kind },
                else => return error.InvalidProgramHeaderKind,
            },
            .permissions = .{
                .executable = permissions & 0x1 != 0,
                .writeable = permissions & 0x2 != 0,
                .readable = permissions & 0x4 != 0,
            },
            .offset = try reader.readInt(u64, endian),
            .virtual_addr = try reader.readInt(u64, endian),
            .physical_addr = try reader.readInt(u64, endian),
            .file_size = try reader.readInt(u64, endian),
            .memory_size = try reader.readInt(u64, endian),
            .alignment = try reader.readInt(u64, endian),
        };
        try program_headers.append(header);
    }
}
