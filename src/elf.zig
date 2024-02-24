const std = @import("std");

pub fn parseElf(reader: anytype) !void {
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
    _ = try reader.readInt(u64, endian); // phoff
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

    _ = try reader.readInt(u16, endian); // phnum

    switch (try reader.readInt(u16, endian)) {
        0x40 => {},
        else => return error.UnsupportedSectionHeaderTableEntrySize,
    }

    _ = try reader.readInt(u16, endian); // shnum
    _ = try reader.readInt(u16, endian); // shstrndx
}
