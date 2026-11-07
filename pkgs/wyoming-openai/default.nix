{
  lib,
  fetchFromGitHub,
  fetchPypi,
  python3Packages,
  rustPlatform,
  writeShellApplication,
}:

# A Wyoming protocol server that proxies speech-to-text and text-to-speech to
# OpenAI-compatible endpoints, so that Home Assistant's voice pipeline can use
# any server speaking OpenAI's audio API. Home Assistant's own Wyoming
# integration connects to it like any other Wyoming service.
#
# Upstream publishes pure-Python wheels, which are used directly. Upstream also
# pins its dependencies more tightly than nixpkgs can satisfy, so the versions
# it asks for are defined here rather than as separate packages, since nothing
# else uses them. The dependency list is deliberately not relaxed, which makes
# the build fail when a new release asks for something these no longer provide.
let
  py = python3Packages;

  fetchWheel =
    {
      pname,
      version,
      python ? "py3",
      hash,
    }:
    fetchPypi {
      inherit
        pname
        version
        python
        hash
        ;
      format = "wheel";
      dist = python;
    };

  # nixpkgs carries a newer major version than the `openai` Realtime extra and
  # wyoming_openai both allow. The test suite is skipped because the nixpkgs
  # list of disabled tests is written for the newer version.
  websockets = py.websockets.overridePythonAttrs (_: rec {
    version = "15.0.1";
    src = fetchFromGitHub {
      owner = "aaugustin";
      repo = "websockets";
      tag = version;
      hash = "sha256-DC1nK+TvCoCqchyWJOyT4Ul4gkTYXixu7XmTqvytqEo=";
    };
    doCheck = false;
  });

  # nixpkgs carries an older version than `openai` requires. The sdist is used
  # because it includes a Cargo.lock, which the upstream repository does not
  # provide, and it does not include the test suite.
  jiter = py.jiter.overridePythonAttrs (_: rec {
    version = "0.19.0";
    src = fetchPypi {
      pname = "jiter";
      inherit version;
      hash = "sha256-ujBk+L4nbXz7g8L7hchYvlM9osL4D5sEjDeBtFpXoZU=";
    };
    postPatch = "";
    # The sdist's pyproject.toml is at the root and names the module. Building
    # from the subdirectory would skip it and install the module under the
    # name of the crate instead.
    buildAndTestSubdir = null;
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "jiter-${version}-vendor";
      hash = "sha256-5HFH/uoN2UKsJFQ6k1rrD6KBYkvWX8NUZgiBgxOXeLo=";
    };
    doCheck = false;
  });

  openai = py.buildPythonPackage rec {
    pname = "openai";
    version = "3.44.0";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-DuviVYF3NGH+etDl+lNxO16fWcQPzLySRs+C//cr/9k=";
    };
    dependencies = [
      py.anyio
      py.httpx2
      jiter
      py.pydantic
      py.sniffio
      py.typing-extensions
      # The `realtime` extra, used by the realtime transcription path.
      websockets
    ];
    pythonImportsCheck = [ "openai" ];
    meta.license = lib.licenses.asl20;
  };

  wyoming = py.buildPythonPackage rec {
    pname = "wyoming";
    version = "1.11.0";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-7OXvhWA9gRGLwtUGea0a7eh78k9qxepxCtlFd9IBaN0=";
    };
    pythonImportsCheck = [ "wyoming" ];
    meta.license = lib.licenses.mit;
  };

  retrie = py.buildPythonPackage rec {
    pname = "retrie";
    version = "0.3.1";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      python = "py2.py3";
      hash = "sha256-y2ejlPk+ZtPuNVksDGUZL4wdfzbmqY5zMG5Dnpe/jZ0=";
    };
    pythonImportsCheck = [ "retrie" ];
    meta.license = lib.licenses.mit;
  };

  radicli = py.buildPythonPackage rec {
    pname = "radicli";
    version = "0.0.26";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-Qvqqn81DBlO+cvZM3Pc8EF6bGeqgzV/6JxnZEUS1L5Y=";
    };
    pythonImportsCheck = [ "radicli" ];
    meta.license = lib.licenses.mit;
  };

  # Sentence boundary detection, used to split replies into sentences so that
  # speech can start playing before the whole reply has been synthesized.
  yasbd-lib = py.buildPythonPackage rec {
    pname = "yasbd_lib";
    version = "1.0.5";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-a1k5EUuKESis3/hCWSfketxU+OX+W3w03IuQCcckaQg=";
    };
    dependencies = [
      radicli
      py.regex
      retrie
    ];
    pythonImportsCheck = [ "yasbd" ];
    meta.license = lib.licenses.mpl20;
  };

  wyoming-openai = py.buildPythonPackage rec {
    pname = "wyoming_openai";
    version = "0.9.0";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-UHCbVrVJ5uW4W8qZPa34prRU8hBfbgbiJEqNtSZrkMk=";
    };

    dependencies = [
      openai
      websockets
      wyoming
      yasbd-lib
    ];

    pythonImportsCheck = [ "wyoming_openai" ];
  };

  pythonEnv = py.python.withPackages (_: [ wyoming-openai ]);
in
# The package defines no console script, so the server is run as a module.
writeShellApplication {
  name = "wyoming-openai";
  text = ''
    exec ${pythonEnv}/bin/python -m wyoming_openai "$@"
  '';

  derivationArgs.passthru = {
    inherit wyoming-openai yasbd-lib;
  };

  meta = {
    description = "Wyoming protocol proxy to OpenAI-compatible speech-to-text and text-to-speech APIs";
    homepage = "https://github.com/roryeckel/wyoming_openai";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    mainProgram = "wyoming-openai";
  };
}
