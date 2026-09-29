{
  lib,
  fetchPypi,
  python3Packages,
  writeShellApplication,
}:

# A Wyoming protocol server that proxies speech-to-text and text-to-speech to
# OpenAI-compatible endpoints, so that Home Assistant's voice pipeline can use
# any server speaking OpenAI's audio API. Home Assistant's own Wyoming
# integration connects to it like any other Wyoming service.
#
# Upstream publishes pure-Python wheels, which are used directly. Two of the
# sentence splitter's dependencies are not in nixpkgs, so they are defined here
# alongside it rather than as separate packages, since nothing else uses them.
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
    version = "0.16.2";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-+BGGqny2X+X7rUwWo3XkLaiAdY6raArNTNLjAs8ZxTM=";
    };
    dependencies = [
      py.beartype
      py.ftfy
      py.loguru
      radicli
      py.regex
      retrie
    ];
    pythonImportsCheck = [ "yasbd" ];
    meta.license = lib.licenses.mpl20;
  };

  wyoming-openai = py.buildPythonPackage rec {
    pname = "wyoming_openai";
    version = "0.6.1";
    format = "wheel";
    src = fetchWheel {
      inherit pname version;
      hash = "sha256-cTZDFfKEN3Km+AoY9MQedJQubWFJKCWGBjvXGJtkyy4=";
    };

    dependencies = [
      py.openai
      # The `openai[realtime]` extra, used by the realtime transcription path.
      py.websockets
      py.wyoming
      yasbd-lib
    ];

    # Upstream pins exact versions of each dependency. nixpkgs carries newer
    # releases of openai, and the API surface used here is stable across them.
    pythonRelaxDeps = [
      "openai"
      "wyoming"
      "yasbd-lib"
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
