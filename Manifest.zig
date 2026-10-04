const std = @import("std");
const Manifest = @This();

source_files: ?[]const []const u8 = null,
common_include_dirs: ?[]const []const u8 = null,
common: ?[]const u32 = null,
os: ?Os = null,
libs: ?Libs = null,

pub const Os = struct {
    linux: ?[]const u32 = null,
    macos: ?[]const u32 = null,
    windows: ?[]const u32 = null,
};

pub const Libs = struct {
    openssl: ?[]const u32 = null,
    zlib: ?[]const u32 = null,
};

pub const ModuleSourceList = struct {
    files: []const []const u8,
    include_dirs: []const []const u8,
};

pub fn selectModuleSources(
    manifest: Manifest,
    allocator: std.mem.Allocator,
    os_tag: std.Target.Os.Tag,
    zlib: bool,
    openssl: bool,
) ModuleSourceList {
    const os_indices = if (manifest.os) |os| switch (os_tag) {
        .linux => os.linux,
        .macos => os.macos,
        .windows => os.windows,
        else => @panic("unsupported OS for module sources"),
    } orelse &.{} else &.{};
    const common_indices = manifest.common orelse &.{};
    const openssl_indices = if (openssl) (if (manifest.libs) |l| l.openssl orelse &.{} else &.{}) else &.{};
    const zlib_indices = if (zlib) (if (manifest.libs) |l| l.zlib orelse &.{} else &.{}) else &.{};

    const total_indices = common_indices.len + os_indices.len + openssl_indices.len + zlib_indices.len;
    const source_files = manifest.source_files orelse &.{};
    var files = std.ArrayList([]const u8).initCapacity(
        allocator,
        total_indices,
    ) catch @panic("OOM");
    for (common_indices) |index| {
        if (index >= source_files.len) @panic("module manifest source index is out of bounds");
        files.append(allocator, source_files[index]) catch @panic("OOM");
    }
    for (os_indices) |index| {
        if (index >= source_files.len) @panic("module manifest source index is out of bounds");
        files.append(allocator, source_files[index]) catch @panic("OOM");
    }
    if (openssl) {
        for (openssl_indices) |index| {
            if (index >= source_files.len) @panic("module manifest source index is out of bounds");
            files.append(allocator, source_files[index]) catch @panic("OOM");
        }
    }
    if (zlib) {
        for (zlib_indices) |index| {
            if (index >= source_files.len) @panic("module manifest source index is out of bounds");
            files.append(allocator, source_files[index]) catch @panic("OOM");
        }
    }
    return .{
        .files = files.toOwnedSlice(allocator) catch @panic("OOM"),
        .include_dirs = manifest.common_include_dirs orelse &.{},
    };
}
