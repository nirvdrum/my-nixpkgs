{
  lib,
  buildGo127Module,
  fetchFromGitHub,
}:

buildGo127Module (finalAttrs: {
  pname = "truenas-mcp";
  version = "0.0.7";

  src = fetchFromGitHub {
    owner = "truenas";
    repo = "truenas-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2gUcvUQFHO3H1GmZsJton86v0NaRuLRsWrEbcs0X5TI=";
  };

  vendorHash = "sha256-L7+NJP3SAL0fNvxH12E8Ak8tf6oKe5zUVHdXXteUIh8=";

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
