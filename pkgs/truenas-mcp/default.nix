{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "truenas-mcp";
  version = "0.0.6";

  src = fetchFromGitHub {
    owner = "truenas";
    repo = "truenas-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-xEiEyUShMVO6OO1/c1sUhhamXjjb+Bss4eNCEil7d4c=";
  };

  vendorHash = "sha256-0A+zS5N+LZ7yRabl6BvovpZPq9NErroW21sRfiMTA+c=";

  subPackages = [ "cmd/truenas-mcp" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${finalAttrs.version}"
  ];

  postInstall = ''
    install -Dm444 docs/examples.md -t $out/share/doc/${finalAttrs.pname}
    install -Dm444 docs/full-features.md -t $out/share/doc/${finalAttrs.pname}
    install -Dm444 mcp-config.example.json -t $out/share/doc/${finalAttrs.pname}
  '';

  meta = {
    description = "MCP server for monitoring and managing a TrueNAS system via an LLM";
    homepage = "https://github.com/truenas/truenas-mcp";
    license = lib.licenses.gpl3Only;
    mainProgram = "truenas-mcp";
    platforms = lib.platforms.unix;
  };
})
