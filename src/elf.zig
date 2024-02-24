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

const SectionHeader = struct {
    name: u32,
    kind: union(enum) {
        unused,
        progbits,
        symtab,
        strtab,
        rela,
        hash,
        dynamic,
        note,
        nobits,
        rel,
        shlib,
        dynsym,
        init_array,
        fini_array,
        preinit_array,
        group,
        symtab_shndx,
        num,
        os: u32,
    },
    attributes: packed struct {
        writeable: bool,
        alloc: bool,
        executable: bool,
        merge: bool,
        strings: bool,
        info_link: bool,
        link_order: bool,
        os_nonconforming: bool,
        group: bool,
        tls: bool,
        maskos: bool,
        maskproc: bool,
        ordered: bool,
        exclude: bool,
    },
    addr: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    alignment: u64,
    entry_size: u64,
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

    const phoff: u64 = 64;
    switch (try reader.readInt(u64, endian)) {
        phoff => {},
        else => return error.UnsupportedProgramHeaderTableOffset,
    }

    const shoff = try reader.readInt(u64, endian);
    if (shoff > 10000) {
        return error.SectionHeaderOffsetTooLarge;
    }

    _ = try reader.readInt(u32, endian); // flags

    switch (try reader.readInt(u16, endian)) {
        64 => {},
        else => return error.UnsupportedHeaderSize,
    }

    const phent_size: u64 = 0x38;
    switch (try reader.readInt(u16, endian)) {
        phent_size => {},
        else => return error.UnsupportedProgramHeaderTableEntrySize,
    }

    const phnum = try reader.readInt(u16, endian);
    if (phnum > 32) {
        return error.TooManyProgramHeaderTableEntries;
    }

    const shent_size: u64 = 0x40;
    switch (try reader.readInt(u16, endian)) {
        shent_size => {},
        else => return error.UnsupportedSectionHeaderTableEntrySize,
    }

    const shnum = try reader.readInt(u16, endian);
    if (shnum > 32) {
        return error.TooManySectionHeaderTableEntries;
    }

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

    // sections

    const section_start_pos = phoff + (phnum * phent_size);
    if (shoff < section_start_pos) {
        return error.InvalidSectionHeaderOffset;
    }
    try reader.skipBytes(shoff - section_start_pos, .{});

    // section headers

    var section_headers = std.ArrayList(SectionHeader).init(allocator);
    defer section_headers.deinit();
    for (0..shnum) |_| {
        const name = try reader.readInt(u32, endian);
        const kind = try reader.readInt(u32, endian);
        const attributes = try reader.readInt(u64, endian);
        const header = SectionHeader{
            .name = name,
            .kind = switch (kind) {
                0x0 => .unused,
                0x1 => .progbits,
                0x2 => .symtab,
                0x3 => .strtab,
                0x4 => .rela,
                0x5 => .hash,
                0x6 => .dynamic,
                0x7 => .note,
                0x8 => .nobits,
                0x9 => .rel,
                0x0A => .shlib,
                0x0B => .dynsym,
                0x0E => .init_array,
                0x0F => .fini_array,
                0x10 => .preinit_array,
                0x11 => .group,
                0x12 => .symtab,
                0x13 => .num,
                0x60000000...std.math.maxInt(u32) => .{ .os = kind },
                else => return error.InvalidSectionHeaderKind,
            },
            .attributes = .{
                .writeable = attributes & 0x1 != 0,
                .alloc = attributes & 0x2 != 0,
                .executable = attributes & 0x4 != 0,
                .merge = attributes & 0x10 != 0,
                .strings = attributes & 0x20 != 0,
                .info_link = attributes & 0x40 != 0,
                .link_order = attributes & 0x80 != 0,
                .os_nonconforming = attributes & 0x100 != 0,
                .group = attributes & 0x200 != 0,
                .tls = attributes & 0x400 != 0,
                .maskos = attributes & 0x0FF00000 != 0,
                .maskproc = attributes & 0xF0000000 != 0,
                .ordered = attributes & 0x4000000 != 0,
                .exclude = attributes & 0x8000000 != 0,
            },
            .addr = try reader.readInt(u64, endian),
            .offset = try reader.readInt(u64, endian),
            .size = try reader.readInt(u64, endian),
            .link = try reader.readInt(u32, endian),
            .info = try reader.readInt(u32, endian),
            .alignment = try reader.readInt(u64, endian),
            .entry_size = try reader.readInt(u64, endian),
        };
        if (header.offset != 0 and header.size != 0) {
            if (header.offset < section_start_pos or header.offset >= shoff) {
                return error.InvalidSectionOffset;
            }
            if (header.offset + header.size > shoff) {
                return error.InvalidSectionSize;
            }
        }
        try section_headers.append(header);
    }
}
