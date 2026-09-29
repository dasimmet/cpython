const os_names = [_][]const u8{ "linux", "macos", "windows" };
const config_names = [_][]const u8{ "none", "zlib", "openssl", "zlib_openssl" };
const Manifest = @import("Manifest.zig");

const ModuleList = struct {
    files: std.ArrayList([]const u8) = .empty,
    include_dirs: std.ArrayList([]const u8) = .empty,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    var args = try init.minimal.args.iterateAllocator(allocator);
    _ = args.next();

    var module_lists: [os_names.len][config_names.len]ModuleList = undefined;
    for (&module_lists) |*row| {
        for (row) |*module_list| module_list.* = .{};
    }

    while (args.next()) |os_name| {
        if (std.mem.eql(u8, os_name, "--")) break;
        const config_name = args.next() orelse return error.MissingConfigName;
        const input_path = args.next() orelse return error.MissingInputPath;
        const os_index = indexOf(&os_names, os_name) orelse return error.UnsupportedOS;
        const config_index = indexOf(&config_names, config_name) orelse return error.UnsupportedConfig;
        const module_list = &module_lists[os_index][config_index];
        const input = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, allocator, .unlimited);
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
    const output_path = args.next() orelse return error.MissingOutputPath;

    var source_files: std.ArrayList([]const u8) = .empty;
    var common_include_dirs: std.ArrayList([]const u8) = .empty;
    for (module_lists) |row| {
        for (row) |module_list| {
            for (module_list.files.items) |path| {
                if (!contains(source_files.items, path)) try source_files.append(allocator, path);
            }
        }
    }
    for (module_lists[0][0].include_dirs.items) |path| {
        if (contains(common_include_dirs.items, path)) continue;
        var is_common = true;
        for (module_lists) |row| for (row) |module_list| {
            if (!contains(module_list.include_dirs.items, path)) is_common = false;
        };
        if (is_common) try common_include_dirs.append(allocator, path);
    }

    const source_file_paths = try source_files.toOwnedSlice(allocator);
    const common_include_paths = try common_include_dirs.toOwnedSlice(allocator);
    const manifest: Manifest = .{
        .source_files = if (source_file_paths.len == 0) null else source_file_paths,
        .common_include_dirs = if (common_include_paths.len == 0) null else common_include_paths,
        .linux = try makeOs(allocator, module_lists[0], source_file_paths, common_include_paths),
        .macos = try makeOs(allocator, module_lists[1], source_file_paths, common_include_paths),
        .windows = try makeOs(allocator, module_lists[2], source_file_paths, common_include_paths),
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

fn makeOs(allocator: std.mem.Allocator, module_lists: [config_names.len]ModuleList, source_files: []const []const u8, common_include_dirs: []const []const u8) !?Manifest.Os {
    const configs = Manifest.Os{
        .none = try makeLibSet(allocator, module_lists[0], source_files, common_include_dirs),
        .zlib = try makeLibSet(allocator, module_lists[1], source_files, common_include_dirs),
        .openssl = try makeLibSet(allocator, module_lists[2], source_files, common_include_dirs),
        .zlib_openssl = try makeLibSet(allocator, module_lists[3], source_files, common_include_dirs),
    };
    if (configs.none == null and configs.zlib == null and configs.openssl == null and configs.zlib_openssl == null) return null;
    return configs;
}

fn makeLibSet(allocator: std.mem.Allocator, module_list: ModuleList, source_files: []const []const u8, common_include_dirs: []const []const u8) !?Manifest.LibSet {
    var source_file_indices: std.ArrayList(u32) = .empty;
    for (module_list.files.items) |path| {
        const index = indexOf(source_files, path) orelse return error.MissingSourceIndex;
        try source_file_indices.append(allocator, @intCast(index));
    }
    var include_dirs: std.ArrayList([]const u8) = .empty;
    for (module_list.include_dirs.items) |path| {
        if (!contains(common_include_dirs, path)) try include_dirs.append(allocator, path);
    }
    const source_indices = try source_file_indices.toOwnedSlice(allocator);
    const specific_include_dirs = try include_dirs.toOwnedSlice(allocator);
    if (source_indices.len == 0 and specific_include_dirs.len == 0) return null;
    return .{
        .source_file_indices = if (source_indices.len == 0) null else source_indices,
        .include_dirs = if (specific_include_dirs.len == 0) null else specific_include_dirs,
    };
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

const std = @import("std");
