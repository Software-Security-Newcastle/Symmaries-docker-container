# syntax=docker/dockerfile:1

# Standalone precompiled JSymCompiler + Symmaries toolchain.
#
# A single container invocation performs:
#
#   1. JSymCompiler frontend generation
#   2. Validation of the generated frontend inputs
#   3. Execution of the generated Symmaries command
#   4. Validation of the principal Symmaries outputs
#
# The image is assembled from precompiled artefacts stored under bin/.

FROM eclipse-temurin:17-jre-noble AS toolchain-runtime

ENV SYMMARIES_PATH=/opt/symmaries/syrs
ENV JSYMCOMPILER_JAR=/app/JSymCompiler.jar
ENV SYMMARIES_VARIANT=
ENV SYMMARIES_HEAP_DOMAIN=deepalias

WORKDIR /work

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        libgmp10 \
        libmpfr6 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p \
        /app \
        /input \
        /output \
        /work \
        /opt/symmaries/lib \
    && chmod 0755 \
        /app \
        /input \
        /output \
        /work \
        /opt/symmaries \
        /opt/symmaries/lib

COPY bin/syrs /opt/symmaries/syrs
COPY bin/JSymCompiler.jar /app/JSymCompiler.jar
COPY bin/lib/ /opt/symmaries/lib/
COPY bin/SHA256SUMS /tmp/SHA256SUMS

RUN chmod 0755 /opt/symmaries/syrs \
    && ln -s /opt/symmaries/syrs /opt/symmaries/syrs.native \
    && ln -s /opt/symmaries/syrs /opt/symmaries/syrs.opt \
    && cp /opt/symmaries/lib/lib*.so* /usr/lib/ \
    && ldconfig \
    && test -s /app/JSymCompiler.jar \
    && test -x /opt/symmaries/syrs

# Verify the repository-provided artefacts using rewritten container paths.
RUN sed \
        -e 's|  bin/syrs$|  /opt/symmaries/syrs|' \
        -e 's|  bin/JSymCompiler.jar$|  /app/JSymCompiler.jar|' \
        -e 's|  bin/lib/|  /opt/symmaries/lib/|' \
        /tmp/SHA256SUMS \
        > /tmp/container-SHA256SUMS \
    && sha256sum --check --strict /tmp/container-SHA256SUMS \
    && rm -f /tmp/SHA256SUMS /tmp/container-SHA256SUMS

# Fail the build if any required native dependency cannot be resolved.
RUN set -eu; \
    ldd_output="$(ldd /opt/symmaries/syrs 2>&1)"; \
    printf '%s\n' "$ldd_output"; \
    if printf '%s\n' "$ldd_output" \
        | grep -qE 'not found|GLIBC_[0-9.]+.*not found'; \
    then \
        echo "Symmaries has unresolved native requirements." >&2; \
        exit 1; \
    fi; \
    /opt/symmaries/syrs -V; \
    test -s /app/JSymCompiler.jar

RUN cat > /usr/local/bin/run-jsymcompiler <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

show_container_help() {
    cat <<'HELP'
Standalone JSymCompiler + Symmaries container

Usage:
  docker run [Docker options] IMAGE <input.jar|input.apk> [options]

A single invocation performs:

  1. JSymCompiler frontend generation
  2. Validation of the generated frontend files
  3. Symmaries analysis using syrsCommand.command
  4. Validation of the principal Symmaries outputs

The Symmaries executable is automatically supplied as:

  -sp /opt/symmaries/syrs

Common JSymCompiler options:
  -o <dir>          Output directory
  -ss <file>        Sources/Sinks XML
  -tf <file>        Security summary stub; repeatable
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

Container environment overrides:
  SYMMARIES_VARIANT
      Optional suffix used for generated result names.
      Default: empty.

  SYMMARIES_HEAP_DOMAIN
      Heap domain supplied to the generated Symmaries command.
      Default: deepalias.

Linux example:
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --mount type=bind,src="$PWD/example",dst=/test \
    symmaries-toolchain:development \
    /test/program.jar \
    -ss /test/rifl.xml \
    -o /test/Syrs

On Windows Docker Desktop, omit the --user option.
HELP
}

if [ "$#" -eq 0 ]; then
    show_container_help
    exit 0
fi

case "$1" in
    -h|--help)
        show_container_help
        exit 0
        ;;
esac

input_file="$1"

if [ ! -f "$input_file" ]; then
    echo "Error: input file does not exist:" >&2
    echo "  ${input_file}" >&2
    exit 1
fi

case "$input_file" in
    *.jar|*.apk)
        ;;
    *)
        echo "Error: input must be a .jar or .apk file:" >&2
        echo "  ${input_file}" >&2
        exit 1
        ;;
esac

if [ ! -s "${JSYMCOMPILER_JAR}" ]; then
    echo "Error: JSymCompiler is missing or empty:" >&2
    echo "  ${JSYMCOMPILER_JAR}" >&2
    exit 1
fi

if [ ! -x "${SYMMARIES_PATH}" ]; then
    echo "Error: Symmaries is missing or not executable:" >&2
    echo "  ${SYMMARIES_PATH}" >&2
    exit 1
fi

output_directory=""

arguments=("$@")
argument_count="${#arguments[@]}"

for ((index = 0; index < argument_count; index++)); do
    if [ "${arguments[$index]}" = "-o" ]; then
        next_index=$((index + 1))

        if [ "$next_index" -ge "$argument_count" ]; then
            echo "Error: -o requires an output directory." >&2
            exit 1
        fi

        output_directory="${arguments[$next_index]}"
    fi
done

if [ -z "$output_directory" ]; then
    input_parent="$(dirname "$input_file")"
    output_directory="${input_parent}/Syrs"
fi

command_directory="$(dirname "$output_directory")"

if [ ! -d "$command_directory" ]; then
    echo "Error: output parent directory does not exist:" >&2
    echo "  ${command_directory}" >&2
    exit 1
fi

if [ ! -w "$command_directory" ]; then
    echo "Error: output parent directory is not writable:" >&2
    echo "  ${command_directory}" >&2
    echo >&2
    echo "On Linux, run Docker with:" >&2
    echo '  --user "$(id -u):$(id -g)"' >&2
    exit 1
fi

echo "============================================================"
echo "Running JSymCompiler frontend"
echo "Input:             ${input_file}"
echo "Output:            ${output_directory}"
echo "Symmaries:         ${SYMMARIES_PATH}"
echo "Runtime UID:GID:   $(id -u):$(id -g)"
echo "============================================================"

java -jar "${JSYMCOMPILER_JAR}" \
    "$@" \
    -sp "${SYMMARIES_PATH}"

if [ ! -d "$output_directory" ]; then
    echo "Error: JSymCompiler did not create the output directory:" >&2
    echo "  ${output_directory}" >&2
    exit 1
fi

command_file="${output_directory}/syrsCommand.command"

if [ ! -s "$command_file" ]; then
    echo "Error: JSymCompiler did not generate the Symmaries command:" >&2
    echo "  ${command_file}" >&2
    exit 1
fi

for frontend_file in \
    "${output_directory}/types.classes" \
    "${output_directory}/Meth/all.secstubs" \
    "${output_directory}/Meth/all.meth_files"
do
    if [ ! -s "$frontend_file" ]; then
        echo "Error: required JSymCompiler output is missing or empty:" >&2
        echo "  ${frontend_file}" >&2
        exit 1
    fi
done

export variant="${SYMMARIES_VARIANT:-}"
export heapDomain="${SYMMARIES_HEAP_DOMAIN:-deepalias}"

echo
echo "============================================================"
echo "JSymCompiler frontend completed"
echo "Running generated Symmaries command"
echo "Command file:      ${command_file}"
echo "Working directory: ${command_directory}"
echo "Variant:           ${variant:-<empty>}"
echo "Heap domain:       ${heapDomain}"
echo "============================================================"

(
    cd "$command_directory"
    bash "$command_file"
)

echo
echo "============================================================"
echo "Symmaries command completed"
echo "Validating Symmaries outputs"
echo "============================================================"

validation_failed=false

for expected_file in \
    "${output_directory}/types.classes_bin" \
    "${output_directory}/types.class_stats" \
    "${output_directory}/results${variant}.secsums" \
    "${output_directory}/results${variant}.meth_stats" \
    "${output_directory}/results${variant}.syrs-version"
do
    if [ ! -e "$expected_file" ]; then
        echo "Error: expected Symmaries output is missing:" >&2
        echo "  ${expected_file}" >&2
        validation_failed=true
    elif [ ! -s "$expected_file" ]; then
        echo "Warning: Symmaries output exists but is empty:" >&2
        echo "  ${expected_file}" >&2
    else
        echo "Present: ${expected_file}"
    fi
done

if [ "$validation_failed" = true ]; then
    echo "Error: Symmaries did not produce all expected outputs." >&2
    exit 1
fi

echo
echo "JSymCompiler and Symmaries analysis completed successfully"
echo "Results: ${output_directory}"
EOF

# Normalise the generated entrypoint for builds from Windows checkouts.
RUN sed -i 's/\r$//' /usr/local/bin/run-jsymcompiler \
    && chmod 0755 /usr/local/bin/run-jsymcompiler

ENTRYPOINT ["/usr/local/bin/run-jsymcompiler"]
