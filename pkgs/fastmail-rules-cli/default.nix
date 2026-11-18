{ lib, buildGoModule, fetchFromGitHub, installShellFiles }:

buildGoModule rec {
  pname = "fastmail-sieve";
  version = "unstable-2026-11-15";

  src = fetchFromGitHub {
    owner = "dvcrn";
    repo = "fastmail-rules-cli";
    rev = "dad9a0dccee9ac3d36b20a1b67e9a1d77216e5be";
    hash = "sha256-x1Z0m1qKEbkTE+WBKlpdokag09d2cl9BSKUmam+MGVA=";
  };

  vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";

  nativeBuildInputs = [ installShellFiles ];

  # Upstream renamed its Go module from fastmail-sieve to fastmail-rules-cli,
  # which changed the name of the built binary. The CLI itself, its completions,
  # and its config directory all still call themselves fastmail-sieve, so restore
  # that name rather than making users learn a second one.
  postInstall = ''
    mv $out/bin/fastmail-rules-cli $out/bin/fastmail-sieve

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
