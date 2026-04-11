{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
  makeWrapper,
  installShellFiles,
}:

rustPlatform.buildRustPackage {
  pname = "deadbranch";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "armgabrielyan";
    repo = "deadbranch";
    tag = "v0.3.0";
    hash = "sha256-8KNo/6hdeBY8RbLlXt2gpLCk2DfvSuoeXJ0oh2NDX2s=";
  };

  cargoHash = "sha256-iY39RBA0fl/BpX6mlCH2bHuN+XsLdq4f7CTzjHz9Ots=";

  nativeBuildInputs = [
    git
    makeWrapper
    installShellFiles
  ];

  # The test suite creates git repos and deadbranch writes config to $HOME.
  # The Nix sandbox sets HOME to /homeless-shelter (read-only), so we
  # redirect it to a writable temporary directory.
  preCheck = ''
    export HOME=$(mktemp -d)
    git config --global user.email "test@test.com"
    git config --global user.name "Test"
    git config --global init.defaultBranch main
  '';

  postInstall = ''
    wrapProgram $out/bin/deadbranch \
      --prefix PATH : ${lib.makeBinPath [ git ]}

    $out/bin/deadbranch completions bash > deadbranch.bash
    $out/bin/deadbranch completions zsh > _deadbranch
    $out/bin/deadbranch completions fish > deadbranch.fish
    installShellCompletion --bash --name deadbranch deadbranch.bash --zsh _deadbranch --fish deadbranch.fish

    local build_dir
    build_dir=$(find target -path '*/build/deadbranch-*/out/deadbranch.1' -print -quit)
    if [ -n "$build_dir" ]; then
      installManPage "$build_dir"
    fi
  '';

  meta = {
    description = "CLI tool for safely cleaning up stale git branches";
    homepage = "https://github.com/armgabrielyan/deadbranch";
    license = lib.licenses.mit;
    mainProgram = "deadbranch";
    platforms = lib.platforms.unix;
  };
}
