const Manifest = @This();

source_files: ?[]const []const u8 = null,
common_include_dirs: ?[]const []const u8 = null,
linux: ?Os = null,
macos: ?Os = null,
windows: ?Os = null,

pub const Os = struct {
    none: ?LibSet = null,
    zlib: ?LibSet = null,
    openssl: ?LibSet = null,
    zlib_openssl: ?LibSet = null,
};

pub const LibSet = struct {
    source_file_indices: ?[]const u32 = null,
    include_dirs: ?[]const []const u8 = null,
};
