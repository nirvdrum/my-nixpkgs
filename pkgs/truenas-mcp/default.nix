{
  lib,
  buildGo127Module,
  go_1_27,
  fetchFromGitHub,
  fetchurl,
}:

let
  # Upstream's go.mod requires Go 1.27.4, but nixpkgs still ships 1.27.3 for
  # the 1.27 series. Building the newer point release from source avoids
  # weakening the go.mod requirement. Drop this once nixpkgs catches up.
  go = go_1_27.overrideAttrs (_: rec {
    version = "1.27.4";
    src = fetchurl {
      url = "https://go.dev/dl/go${version}.src.tar.gz";
      hash = "sha256-c8+4VxrsDAEXdofbhxY9Rqog6XeWcncokaoXZU2aYJk=";
    };
  });
in
(buildGo127Module.override { inherit go; }) (finalAttrs: {
  pname = "truenas-mcp";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "truenas";
    repo = "truenas-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-iZS6hqzTQQfCWsdK6f6jf/ItYPU3XNj3NJJNht6DtAM=";
  };

  vendorHash = "sha256-RCcyGLepRB1YMTb6hvAyskYTzHrKlwqjRdnRLfdydls=";

  subPackages = [ "cmd/truenas-mcp" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${finalAttrs.version}"
  ];

  postInstall = ''
    install -Dm444 docs/examples.md -t $out/share/doc/${finalAttrs.pname}
    install -Dm444 docs/full-features.md -t $out/share/doc/${finalAttrs.pname}
    install -Dm444 claude_desktop_config.example.json -t $out/share/doc/${finalAttrs.pname}
  '';

  meta = {
    description = "MCP server for monitoring and managing a TrueNAS system via an LLM";
    homepage = "https://github.com/truenas/truenas-mcp";
    license = lib.licenses.gpl3Only;
    mainProgram = "truenas-mcp";
    platforms = lib.platforms.unix;
  };
})
