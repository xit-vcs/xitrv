const std = @import("std");

pub const ProgramHeader = struct {
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

pub const Symbol = struct {
    kind: union(enum) {
        none,
        object,
        func,
        section,
        file,
        os: u8,
        proc: u8,
    },
    binding: union(enum) {
        local,
        global,
        weak,
        os: u8,
        proc: u8,
    },
    visibility: enum {
        default,
        internal,
        hidden,
        protected,
    },
    name_off: u32,
    name_str: []const u8,
    shndx: u16,
    value: u64,
    size: u64,

    pub fn init(buffer: []const u8, endian: std.builtin.Endian) !Symbol {
        var stream = std.io.fixedBufferStream(buffer);
        const reader = stream.reader();
        const entry_name = try reader.readInt(u32, endian);
        const entry_info = try reader.readInt(u8, endian);
        const kind = entry_info & 0xf;
        const binding = entry_info >> 4;
        const other = try reader.readInt(u8, endian);
        return Symbol{
            .kind = switch (kind) {
                0 => .none,
                1 => .object,
                2 => .func,
                3 => .section,
                4 => .file,
                10...12 => .{ .os = kind },
                13...15 => .{ .proc = kind },
                else => return error.InvalidSymbolKind,
            },
            .binding = switch (binding) {
                0 => .local,
                1 => .global,
                2 => .weak,
                10...12 => .{ .os = binding },
                13...15 => .{ .proc = binding },
                else => return error.InvalidSymbolBinding,
            },
            .visibility = switch (other & 0x03) {
                0 => .default,
                1 => .internal,
                2 => .hidden,
                3 => .protected,
                else => return error.InvalidSymbolVisibility,
            },
            .name_off = entry_name,
            .name_str = undefined,
            .shndx = try reader.readInt(u16, endian),
            .value = try reader.readInt(u64, endian),
            .size = try reader.readInt(u64, endian),
        };
    }
};

pub const Section = struct {
    name_off: usize,
    name_str: []const u8,
    kind: union(enum) {
        unused,
        progbits: struct {
            buffer: []u8,
        },
        symtab,
        strtab: struct {
            offset_to_string: std.AutoArrayHashMap(usize, []const u8),
        },
        rela,
        hash,
        dynamic,
        note,
        nobits,
        rel,
        shlib,
        dynsym: struct {
            symbols: std.ArrayList(Symbol),
        },
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

pub const Elf = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    program_headers: std.ArrayList(ProgramHeader),
    sections: std.ArrayList(Section),
    section_buffer: []u8,
    name_to_dynsym: std.StringArrayHashMap(*Symbol),

    pub fn init(allocator: std.mem.Allocator, reader: anytype) !Elf {
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

        const shstrndx = try reader.readInt(u16, endian);

        // program headers

        var program_headers = std.ArrayList(ProgramHeader).init(allocator);
        errdefer program_headers.deinit();
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
        const section_buffer_len = shoff - section_start_pos;
        if (section_buffer_len > 10_000_000) {
            return error.SectionDataTooLong;
        }
        const section_buffer = try allocator.alloc(u8, section_buffer_len);
        errdefer allocator.free(section_buffer);
        try reader.readNoEof(section_buffer);

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var sections = std.ArrayList(Section).init(allocator);
        errdefer sections.deinit();
        for (0..shnum) |_| {
            const name = try reader.readInt(u32, endian);
            const kind = try reader.readInt(u32, endian);
            const attributes = try reader.readInt(u64, endian);
            const addr = try reader.readInt(u64, endian);
            const offset = try reader.readInt(u64, endian);
            const size = try reader.readInt(u64, endian);
            const link = try reader.readInt(u32, endian);
            const info = try reader.readInt(u32, endian);
            const alignment = try reader.readInt(u64, endian);
            const entry_size = try reader.readInt(u64, endian);
            const section = Section{
                .name_off = name,
                .name_str = undefined,
                .kind = switch (kind) {
                    0x0 => .unused,
                    0x1 => blk: {
                        if (offset < section_start_pos or offset >= shoff) {
                            return error.InvalidSectionOffset;
                        }
                        if (offset + size > shoff) {
                            return error.InvalidSectionSize;
                        }
                        const start_pos = offset - section_start_pos;
                        break :blk .{ .progbits = .{
                            .buffer = section_buffer[start_pos .. start_pos + size],
                        } };
                    },
                    0x2 => .symtab,
                    0x3 => blk: {
                        if (offset < section_start_pos or offset >= shoff) {
                            return error.InvalidSectionOffset;
                        }
                        if (offset + size > shoff) {
                            return error.InvalidSectionSize;
                        }
                        const start_pos = offset - section_start_pos;
                        const buffer = section_buffer[start_pos .. start_pos + size];
                        var offset_to_string = std.AutoArrayHashMap(usize, []const u8).init(arena.allocator());
                        var i: usize = 0;
                        while (i < buffer.len) {
                            if (std.mem.indexOf(u8, buffer[i..], "\x00")) |next_i| {
                                try offset_to_string.put(i, buffer[i .. i + next_i]);
                                i += next_i + 1;
                            } else {
                                try offset_to_string.put(i, buffer[i..]);
                                break;
                            }
                        }
                        break :blk .{ .strtab = .{
                            .offset_to_string = offset_to_string,
                        } };
                    },
                    0x4 => .rela,
                    0x5 => .hash,
                    0x6 => .dynamic,
                    0x7 => .note,
                    0x8 => .nobits,
                    0x9 => .rel,
                    0x0A => .shlib,
                    0x0B => blk: {
                        if (offset < section_start_pos or offset >= shoff) {
                            return error.InvalidSectionOffset;
                        }
                        if (entry_size != 24) {
                            return error.InvalidSectionEntrySize;
                        }
                        if (offset + size > shoff or size % entry_size != 0) {
                            return error.InvalidSectionSize;
                        }
                        const start_pos = offset - section_start_pos;
                        var symbols = std.ArrayList(Symbol).init(arena.allocator());
                        for (0..size / entry_size) |i| {
                            const entry_start_pos = start_pos + (entry_size * i);
                            const buffer = section_buffer[entry_start_pos .. entry_start_pos + entry_size];
                            try symbols.append(try Symbol.init(buffer, endian));
                        }
                        break :blk .{ .dynsym = .{
                            .symbols = symbols,
                        } };
                    },
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
                .addr = addr,
                .offset = offset,
                .size = size,
                .link = link,
                .info = info,
                .alignment = alignment,
                .entry_size = entry_size,
            };
            try sections.append(section);
        }

        // set name_str for sections and symbols
        const section_offset_to_string = &sections.items[shstrndx].kind.strtab.offset_to_string;
        const program_offset_to_string = for (sections.items, 0..) |section, i| {
            if (section.kind == .strtab and i != shstrndx) {
                break &section.kind.strtab.offset_to_string;
            }
        } else {
            return error.ProgramStringsNotFound;
        };
        for (sections.items) |*section| {
            section.name_str = section_offset_to_string.get(section.name_off) orelse return error.SectionStringNotFound;
            if (section.kind == .dynsym) {
                for (section.kind.dynsym.symbols.items) |*symbol| {
                    symbol.name_str = program_offset_to_string.get(symbol.name_off) orelse return error.ProgramStringNotFound;
                }
            }
        }

        var name_to_dynsym = std.StringArrayHashMap(*Symbol).init(allocator);
        errdefer name_to_dynsym.deinit();
        for (sections.items) |section| {
            if (section.kind == .dynsym) {
                for (section.kind.dynsym.symbols.items) |*symbol| {
                    try name_to_dynsym.putNoClobber(symbol.name_str, symbol);
                }
            }
        }

        return .{
            .allocator = allocator,
            .arena = arena,
            .program_headers = program_headers,
            .sections = sections,
            .section_buffer = section_buffer,
            .name_to_dynsym = name_to_dynsym,
        };
    }

    pub fn deinit(self: *Elf) void {
        self.arena.deinit();
        self.program_headers.deinit();
        self.sections.deinit();
        self.allocator.free(self.section_buffer);
        self.name_to_dynsym.deinit();
    }
};
