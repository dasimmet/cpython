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
