# Standalone JSymCompiler and Symmaries Container

This repository packages precompiled **JSymCompiler** and **Symmaries** binaries into a Linux container. The host only needs Docker. Java, OCaml, APRON, GMP and MPFR do not need to be installed directly on the host.

A single container invocation performs the complete workflow:

1. JSymCompiler processes the submitted `.jar` or `.apk`.
2. JSymCompiler writes its frontend files and `syrsCommand.command`.
3. The container validates the generated inputs.
4. The container runs the generated Symmaries command automatically.
5. The container validates the principal Symmaries outputs.

The current precompiled toolchain is for **Linux AMD64** and uses an Ubuntu 24.04 (Noble) runtime because the supplied Symmaries binary requires GLIBC 2.38 or later.

## Repository layout

```text
.
├── Dockerfile
├── README.md
├── TECHNICAL-NOTES.md
├── .gitattributes
├── .gitignore
├── bin
│   ├── JSymCompiler.jar
│   ├── syrs
│   ├── SHA256SUMS
│   └── lib
│       ├── libapron.so
│       ├── libboxMPQ.so
│       ├── liboctMPQ.so
│       └── libpolkaMPQ.so
├── AliasingControlFlowInsecure
│   ├── program.jar
│   └── rifl.xml
└── CallContext
    ├── all.secstubs
    ├── program.jar
    └── rifl.xml
```

The four APRON shared libraries are packaged with `syrs`. The runtime image installs the remaining system libraries through Ubuntu packages.

For architecture support, binary updates, line-ending policy and provenance considerations, see [TECHNICAL-NOTES.md](TECHNICAL-NOTES.md).

## Prerequisites

- Docker Engine or Docker Desktop
- Linux containers enabled on Windows or macOS
- Enough local storage for the base image and packaged toolchain

No GitHub token is required. The binary-based build does not clone or compile the source repositories.

## Build the image

From the repository root:

```bash
docker build --tag symmaries-toolchain:binary .
```

For detailed build output:

```bash
docker build --progress=plain --tag symmaries-toolchain:binary . 2>&1 | tee binary-build.log
```

The build verifies the packaged artefacts against `bin/SHA256SUMS`, checks native library resolution and runs `syrs -V`.

## Verify the image

Show the configured entrypoint:

```bash
docker image inspect symmaries-toolchain:binary --format '{{json .Config.Entrypoint}}'
```

Expected:

```text
["/usr/local/bin/run-jsymcompiler"]
```

Check the Symmaries version:

```bash
docker run --rm --entrypoint /opt/symmaries/syrs symmaries-toolchain:binary -V
```

Check native library resolution:

```bash
docker run --rm --entrypoint ldd symmaries-toolchain:binary /opt/symmaries/syrs
```

Check both packaged tools:

```bash
docker run --rm --entrypoint /bin/bash symmaries-toolchain:binary -c 'set -eu; test -s /app/JSymCompiler.jar; test -x /opt/symmaries/syrs; echo "Precompiled toolchain is present"'
```

## Show container help

Run the image without input:

```bash
docker run --rm symmaries-toolchain:binary
```

Or request help explicitly:

```bash
docker run --rm symmaries-toolchain:binary --help
```

The container displays its own help rather than passing `--help` to JSymCompiler as an input filename.

## Run the combined toolchain on Linux

On Linux, pass the current user's UID and GID so files written to bind-mounted directories remain user-owned.

### AliasingControlFlowInsecure

```bash
cd ~/SymmariesProjectBits/standalone-symmaries
rm -rf AliasingControlFlowInsecure/Syrs
docker run --rm --user "$(id -u):$(id -g)" --mount type=bind,src="$PWD/AliasingControlFlowInsecure",dst=/test symmaries-toolchain:binary /test/program.jar -ss /test/rifl.xml -o /test/Syrs
```

Inspect the summaries:

```bash
find AliasingControlFlowInsecure/Syrs/Meth -type f -name '*.secsum' -printf '%f %s bytes\n' | sort
```

### CallContext

```bash
cd ~/SymmariesProjectBits/standalone-symmaries
rm -rf CallContext/Syrs
docker run --rm --user "$(id -u):$(id -g)" --mount type=bind,src="$PWD/CallContext",dst=/test symmaries-toolchain:binary /test/program.jar -ss /test/rifl.xml -tf /test/all.secstubs -o /test/Syrs
```

Inspect the summaries:

```bash
find CallContext/Syrs/Meth -type f -name '*.secsum' -printf '%f %s bytes\n' | sort
```

## Run the combined toolchain on Windows PowerShell

Use a clone on a local Windows drive, such as `C:`, rather than an SMB-backed network drive. Docker Desktop may be unable to bind-mount a mapped network location.

### Windows Docker setup 
Start Docker Desktop and select Linux containers before building: 

```powershell 
docker desktop start 
docker context use desktop-linux
```

Build:

```powershell
docker build --tag symmaries-toolchain:binary .
```

### AliasingControlFlowInsecure

Set path of folder where doing analysis:
```powershell
$AliasingPath = (Resolve-Path ".\AliasingControlFlowInsecure").Path
```

Remove any preexisting results:
```powershell
Remove-Item -Recurse -Force ".\AliasingControlFlowInsecure\Syrs" -ErrorAction SilentlyContinue
```

Run the tool, giving set path/location:  
(Passes jar-to-analyse, sinks/sources.xml, and output location)
```powershell
docker run --rm --mount "type=bind,src=$AliasingPath,dst=/test" symmaries-toolchain:binary /test/program.jar -ss /test/rifl.xml -o /test/Syrs
```

Fetch summary of result output files:
```powershell
Get-ChildItem ".\AliasingControlFlowInsecure\Syrs\Meth" -Filter "*.secsum" | Select-Object Name, Length
```

### CallContext

Set path of folder where doing analysis:
```powershell
$CallContextPath = (Resolve-Path ".\CallContext").Path
```

Remove any preexisting results:
```powershell
Remove-Item -Recurse -Force ".\CallContext\Syrs" -ErrorAction SilentlyContinue
```

Run the tool, giving set path/location:  
(Passes jar-to-analyse, sinks/sources.xml, and output location)
```powershell
docker run --rm --mount "type=bind,src=$CallContextPath,dst=/test" symmaries-toolchain:binary /test/program.jar -ss /test/rifl.xml -tf /test/all.secstubs -o /test/Syrs
```

Fetch summary of result output files:
```powershell
Get-ChildItem ".\CallContext\Syrs\Meth" -Filter "*.secsum" | Select-Object Name, Length
```

Do not add Linux's `--user "$(id -u):$(id -g)"` option in native PowerShell. Docker Desktop handles Windows bind-mounted ownership differently.

## General invocation

Mount a writable host directory at `/test`, then pass container paths to JSymCompiler:

```bash
docker run --rm --user "$(id -u):$(id -g)" --mount type=bind,src="/ABSOLUTE_PATH/TO/PROJECT",dst=/test symmaries-toolchain:binary /test/APPLICATION.jar -ss /test/RIFL.xml -tf /test/ALL.secstubs -o /test/Syrs
```

The container automatically supplies:

```text
-sp /opt/symmaries/syrs
```

The current JSymCompiler version writes `syrsCommand.command`, and the container executes that command after the frontend completes.

## Common JSymCompiler options

```text
-o <dir>          Output directory
-ss <file>        Sources/Sinks XML
-tf <file>        Security-summary stub; repeatable
-cp <path>        Extra classpath entry
-ap <dir>         Android platforms root for APK input
-analysis <kind>  Analysis mode
+taints           Shortcut for TAINT analysis
-heapdom <kind>   Heap domain
-all              Include all packages
-mvnbuild         Build Maven projects before analysis
-pkg              Include selected packages
-exclClass        Exclude classes
-exclMeth         Exclude methods
-libs             Analyse dependencies
```

If `-o` is omitted, the container follows JSymCompiler's default and uses `<input parent>/Syrs`.

## Container environment overrides

Override the Symmaries heap domain:

```bash
docker run --rm -e SYMMARIES_HEAP_DOMAIN=dumbalias ...
```

Override the optional result-name variant:

```bash
docker run --rm -e SYMMARIES_VARIANT=-experiment ...
```

Defaults:

```text
SYMMARIES_HEAP_DOMAIN=deepalias
SYMMARIES_VARIANT=
```

## Expected output

A successful run reports both phases:

```text
Running JSymCompiler frontend
...
JSymCompiler frontend completed
Running generated Symmaries command
...
Symmaries command completed
...
JSymCompiler and Symmaries analysis completed successfully
```

## Running the current AMD64 image on ARM hosts

The current binary bundle can be used on ARM machines, including Apple Silicon systems, through AMD64 emulation when Docker supports it.

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

If Docker reports a platform mismatch, include `--platform linux/amd64` in both the build and run commands.
