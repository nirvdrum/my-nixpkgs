{ lib, buildGoModule, fetchFromGitHub, installShellFiles }:

buildGoModule rec {
  pname = "fastmail-sieve";
  version = "unstable-2026-04-28";

  src = fetchFromGitHub {
    owner = "dvcrn";
    repo = "fastmail-rules-cli";
    rev = "88cabe134adb250af74d3d8dc4f7a2744f4a9d7e";
    hash = "sha256-he89v2RkLGF0j99yLPyniKA+zm3VNsu1oTnrWtn2JBM=";
  };

  vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    $out/bin/fastmail-sieve completion bash > fastmail-sieve.bash
    $out/bin/fastmail-sieve completion zsh > _fastmail-sieve
    $out/bin/fastmail-sieve completion fish > fastmail-sieve.fish
    installShellCompletion --bash fastmail-sieve.bash --zsh _fastmail-sieve --fish fastmail-sieve.fish
  '';

  meta = with lib; {
    description = "CLI for managing Fastmail mail rules and Sieve scripts through Fastmail's JMAP endpoints";
    homepage = "https://github.com/dvcrn/fastmail-rules-cli";
    license = licenses.unfree;
    mainProgram = "fastmail-sieve";
    platforms = platforms.unix;
  };
}
