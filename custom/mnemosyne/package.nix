{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "mnemosyne-memory";
  version = "3.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "AxDSan";
    repo = "mnemosyne";
    rev = "v${version}";
    hash = "sha256-puQzSOjZ4lV7TnY7GzcBmN3gBDqWfOwoJDyZaKSG8cw=";
  };

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  # Core + MCP + embeddings feature set.
  # The `llm` (ctransformers) and `openclaw` extras are intentionally omitted:
  # those dependencies are not packaged in nixpkgs.
  dependencies = with python3Packages; [
    # core
    numpy
    # embeddings extra (semantic recall)
    fastembed
    sqlite-vec
    huggingface-hub
    # mcp extra
    mcp
    anyio
    # optional-but-handy runtime imports used by core/mcp code paths
    httpx
    tiktoken
    pyyaml
    # SSE transport for `mnemosyne mcp --transport sse`
    starlette
    uvicorn
  ];

  # The project has no importable test suite wired into the build; the `tests/`
  # dir relies on optional/benchmark deps. Just smoke-test the CLI instead.
  doCheck = false;

  # Importing `mnemosyne` eagerly initializes a SQLite DB under the data dir
  # (defaults to ~/.hermes/..., and $HOME is the unwritable /homeless-shelter
  # in the sandbox). The imports check runs right after fixupPhase, so redirect
  # the data dir to a writable build-time location in postFixup.
  postFixup = ''
    export MNEMOSYNE_DATA_DIR="$TMPDIR/mnemosyne-data"
  '';

  pythonImportsCheck = [ "mnemosyne" ];

  meta = {
    description = "Universal, zero-dependency, SQLite-backed AI memory layer for any agent (CLI + MCP server)";
    homepage = "https://github.com/AxDSan/mnemosyne";
    changelog = "https://github.com/AxDSan/mnemosyne/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "mnemosyne";
    platforms = lib.platforms.unix;
  };
}
