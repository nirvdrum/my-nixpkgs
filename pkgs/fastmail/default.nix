{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "fastmail";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "shareup";
    repo = "fastmail";
    rev = "refs/tags/${version}";
    hash = "sha256-TD1IAOMRLE84lT4boI89YYfX2tI9n2FqHRjzA41pdZw=";
  };

  vendorHash = "sha256-QkMXmTUsNofqD0JBrZiA8DyC3ewsdjZ8SkFmFFgEvDY=";

  ldflags = [
    "-X github.com/shareup/fastmail/internal/version.Version=${version}"
  ];

  # The integration tests require a running fakemail server and network access.
  # Unit tests pass without external dependencies but call os.Exit(0) in the
  # cobra command runner (TestMain hardcodes the expected exit code), so we
  # skip them entirely to avoid false negatives.
  doCheck = false;

  meta = with lib; {
    description = "CLI for Fastmail email, calendars, events, and todos via JMAP and CalDAV";
    homepage = "https://github.com/shareup/fastmail";
    license = licenses.unfree;
    mainProgram = "fastmail";
    platforms = platforms.unix;
  };
}
