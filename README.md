# cpython

Builds [cpython](https://github.com/python/cpython) with [Zig](https://ziglang.org/).

There are no system dependencies; the only thing required to build this package is [Zig](https://ziglang.org/).

Supports building a static python executable for linux with the musl abi (i.e. `zig build -Dtarget=x86_64-linux-musl`).

This project also supports building multiple versions of python.

The C sources and include directories selected by makesetup are checked in as version-specific `.zon` files. Each source path is stored once, with target OS and zlib/OpenSSL configurations referring to source indices. To regenerate a manifest, run `zig build update-src -Dversion=<version>` once for each supported version:

```sh
zig build update-src -Dversion=3.11.13
zig build update-src -Dversion=3.12.11
```
