const std = @import("std");
const Manifest = @import("Manifest.zig");

const os_names = std.meta.fieldNames(Manifest.Os);

const ModuleList = struct {
    files: std.ArrayList([]const u8) = .empty,
    include_dirs: std.ArrayList([]const u8) = .empty,
};

const LibInput = struct {
    name: []const u8,
    base_os: []const u8,
    module_list: ModuleList = .{},
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var args = try init.minimal.args.iterateAllocator(allocator);
    _ = args.next();

    var os_lists: [os_names.len]ModuleList = undefined;
    for (&os_lists) |*list| list.* = .{};

    var lib_inputs: std.ArrayList(LibInput) = .empty;

    while (args.next()) |flag| {
        if (std.mem.eql(u8, flag, "--")) break;
        if (std.mem.eql(u8, flag, "--os")) {
            const os_name = args.next() orelse return error.MissingOsName;
            const input_path = args.next() orelse return error.MissingInputPath;
            const os_index = indexOf(os_names, os_name) orelse return error.UnsupportedOS;
            try parseCompileArgs(init.io, allocator, input_path, &os_lists[os_index]);
        } else if (std.mem.eql(u8, flag, "--lib")) {
            const lib_name = args.next() orelse return error.MissingLibName;
            const base_os = args.next() orelse return error.MissingBaseOs;
            const input_path = args.next() orelse return error.MissingInputPath;
            var lib_input: LibInput = .{
                .name = lib_name,
                .base_os = base_os,
            };
            try parseCompileArgs(init.io, allocator, input_path, &lib_input.module_list);
            try lib_inputs.append(allocator, lib_input);
        } else {
            return error.UnsupportedArg;
        }
    }
    const output_path = args.next() orelse return error.MissingOutputPath;

    var source_files: std.ArrayList([]const u8) = .empty;
    var common_include_dirs: std.ArrayList([]const u8) = .empty;

    for (os_lists) |os_list| {
        for (os_list.files.items) |path| {
            if (!contains(source_files.items, path)) try source_files.append(allocator, path);
        }
    }
    for (lib_inputs.items) |lib_input| {
        for (lib_input.module_list.files.items) |path| {
            if (!contains(source_files.items, path)) try source_files.append(allocator, path);
        }
    }

    if (os_lists[0].include_dirs.items.len > 0) {
        for (os_lists[0].include_dirs.items) |path| {
            if (contains(common_include_dirs.items, path)) continue;
            var is_common = true;
            for (os_lists[1..]) |os_list| {
                if (!contains(os_list.include_dirs.items, path)) {
                    is_common = false;
                    break;
                }
            }
            if (is_common) try common_include_dirs.append(allocator, path);
        }
    }

    const source_file_paths = try source_files.toOwnedSlice(allocator);
    const common_include_paths = try common_include_dirs.toOwnedSlice(allocator);

    var common_indices: std.ArrayList(u32) = .empty;
    for (os_lists[0].files.items) |path| {
        var is_common = true;
        for (os_lists[1..]) |os_list| {
            if (!contains(os_list.files.items, path)) {
                is_common = false;
                break;
            }
        }
        if (is_common) {
            const index = indexOf(source_file_paths, path) orelse return error.MissingSourceIndex;
            try common_indices.append(allocator, @intCast(index));
        }
    }

    var openssl_indices: ?[]const u32 = null;
    var zlib_indices: ?[]const u32 = null;
    for (lib_inputs.items) |lib_input| {
        const base_os_index = indexOf(os_names, lib_input.base_os) orelse return error.UnsupportedOS;
        const indices = try makeLibIndices(allocator, lib_input, os_lists[base_os_index], source_file_paths);
        if (std.mem.eql(u8, lib_input.name, "openssl")) {
            openssl_indices = indices;
        } else if (std.mem.eql(u8, lib_input.name, "zlib")) {
            zlib_indices = indices;
        } else return error.UnsupportedLib;
    }

    const os_result: Manifest.Os = .{
        .linux = try makeOsIndices(allocator, os_lists[0], common_indices.items, source_file_paths),
        .macos = try makeOsIndices(allocator, os_lists[1], common_indices.items, source_file_paths),
        .windows = try makeOsIndices(allocator, os_lists[2], common_indices.items, source_file_paths),
    };
    const libs_result: Manifest.Libs = .{
        .openssl = openssl_indices,
        .zlib = zlib_indices,
    };
    const common_slice = try common_indices.toOwnedSlice(allocator);
    const manifest: Manifest = .{
        .source_files = if (source_file_paths.len == 0) null else source_file_paths,
        .common_include_dirs = if (common_include_paths.len == 0) null else common_include_paths,
        .common = if (common_slice.len == 0) null else common_slice,
        .os = if (os_result.linux == null and os_result.macos == null and os_result.windows == null) null else os_result,
        .libs = if (libs_result.openssl == null and libs_result.zlib == null) null else libs_result,
    };

    var file = try std.Io.Dir.cwd().createFile(init.io, output_path, .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(init.io, &buffer);
    const writer = &file_writer.interface;
    try std.zon.stringify.serialize(manifest, .{ .emit_default_optional_fields = false }, writer);
    try writer.writeByte('\n');
    try writer.flush();
}

fn parseCompileArgs(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    module_list: *ModuleList,
) !void {
    const input = try std.Io.Dir.cwd().readFileAlloc(io, input_path, allocator, .unlimited);
    var line_it = std.mem.splitScalar(u8, input, '\n');
    while (line_it.next()) |line| {
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        if (std.mem.endsWith(u8, line, ".c")) {
            try module_list.files.append(allocator, line);
        } else if (std.mem.startsWith(u8, line, "-I")) {
            const path = line[2..];
            const prefix = "$(srcdir)/";
            if (!std.mem.startsWith(u8, path, prefix)) return error.InvalidIncludePath;
            try module_list.include_dirs.append(allocator, path[prefix.len..]);
        } else return error.UnsupportedCompileArg;
    }
}

fn makeOsIndices(
    allocator: std.mem.Allocator,
    os_list: ModuleList,
    common_indices: []const u32,
    source_file_paths: []const []const u8,
) !?[]const u32 {
    var list: std.ArrayList(u32) = .empty;
    for (os_list.files.items) |path| {
        const index: u32 = @intCast(indexOf(source_file_paths, path) orelse return error.MissingSourceIndex);
        if (!containsIndex(common_indices, index)) {
            try list.append(allocator, index);
        }
    }
    const result = try list.toOwnedSlice(allocator);
    if (result.len == 0) return null;
    return result;
}

fn makeLibIndices(
    allocator: std.mem.Allocator,
    lib_input: LibInput,
    base_os_list: ModuleList,
    source_file_paths: []const []const u8,
) !?[]const u32 {
    var list: std.ArrayList(u32) = .empty;
    for (lib_input.module_list.files.items) |path| {
        if (!contains(base_os_list.files.items, path)) {
            const index: u32 = @intCast(indexOf(source_file_paths, path) orelse return error.MissingSourceIndex);
            try list.append(allocator, index);
        }
    }
    const result = try list.toOwnedSlice(allocator);
    if (result.len == 0) return null;
    return result;
}

fn containsIndex(slice: []const u32, target: u32) bool {
    for (slice) |item| {
        if (item == target) return true;
    }
    return false;
}

fn indexOf(values: []const []const u8, value: []const u8) ?usize {
    for (values, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, value)) return index;
    }
    return null;
}

fn contains(paths: []const []const u8, path: []const u8) bool {
    for (paths) |candidate| {
        if (std.mem.eql(u8, candidate, path)) return true;
    }
    return false;
}
