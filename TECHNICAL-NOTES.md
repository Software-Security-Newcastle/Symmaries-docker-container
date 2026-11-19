# Technical Notes

This document contains maintenance, portability and release details for the standalone JSymCompiler and Symmaries container. For the normal build and run commands, see [README.md](README.md).

## Updating the packaged binaries

Copy new artefacts into `bin/`:

```bash
cp /path/to/syrs.native bin/syrs
chmod 0755 bin/syrs
cp /path/to/jsymcompiler-jar-with-dependencies.jar bin/JSymCompiler.jar
```

Copy the APRON libraries required by the new `syrs` binary:

```bash
rm -f bin/lib/*.so bin/lib/*.so.*
ldd bin/syrs | awk '/lib(boxMPQ|apron|octMPQ|polkaMPQ)\.so/ { print $3 }' | while IFS= read -r library; do cp -L "$library" bin/lib/; done
```

Regenerate and verify checksums:

```bash
find bin -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > bin/SHA256SUMS
sha256sum --check --strict bin/SHA256SUMS
```

Then rebuild and rerun both fixtures from the main README.

## Runtime compatibility

The current `syrs` binary requires GLIBC 2.38 or later. The image therefore uses an Ubuntu 24.04 (Noble) Java runtime with GLIBC 2.39.

Do not copy host versions of `libc.so.6`, `libm.so.6` or the dynamic loader into the image. If a future binary requires a newer GLIBC, either use a compatible runtime base or rebuild `syrs` in the oldest Linux environment you intend to support.

A binary compiled against an older GLIBC is generally more portable to newer Linux environments than the reverse.

## Architecture support

### Current support

The packaged `syrs` executable and APRON libraries are Linux AMD64 binaries. The image therefore targets:

```text
linux/amd64
```

This works natively on AMD64 Linux and through Linux containers on AMD64 Windows and Intel macOS.

### Running the current AMD64 image on ARM hosts

The current binary bundle can be used on ARM machines, including Apple Silicon systems, through AMD64 emulation when Docker supports it. This does not provide native ARM performance, but it avoids rebuilding Symmaries and APRON immediately.

Build explicitly for the AMD64 bundle:

```bash
docker build --platform linux/amd64 --tag symmaries-toolchain:binary .
```

Run under AMD64 emulation:

```bash
docker run --platform linux/amd64 ...
```

Example:

```bash
docker run --rm --platform linux/amd64 --mount type=bind,src="$PWD/AliasingControlFlowInsecure",dst=/test symmaries-toolchain:binary /test/program.jar -ss /test/rifl.xml -o /test/Syrs
```

Docker Desktop generally provides the required emulation environment. Performance may be lower than a native ARM64 image, particularly during Symmaries analysis. If Docker reports a platform mismatch, include `--platform linux/amd64` in both the build and run commands.

