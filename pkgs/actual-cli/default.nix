{ lib, buildNpmPackage, nodejs_22, fetchurl }:

buildNpmPackage rec {
  pname = "actual-cli";
  version = "26.7.0";

  # The package is only published to the npm registry (no GitHub release
  # tarball), so we fetch the npm tarball directly. It extracts to a top-level
  # `package/` directory, which we declare as the source root for both the main
  # build and fetchNpmDeps.
  src = fetchurl {
    url = "https://registry.npmjs.org/@actual-app/cli/-/cli-${version}.tgz";
    hash = "sha256-XPXfNj2KhsaRzNusHfkL/u+KOhih/hyQuEx+zxTNsZw=";
  };

  sourceRoot = "package";

  # Upstream ships a pre-built, bundled `dist/cli.js` and no lockfile. We vendor
  # a production package-lock.json (generated with `npm install
  # --package-lock-only --omit=dev`) so fetchNpmDeps can resolve the runtime
  # dependency tree: @actual-app/api and its transitive deps, including the
  # native better-sqlite3 module. The lockfile root name must match the
  # published package name (@actual-app/cli); only its `version` field needs to
  # track the derivation version, which the update app rewrites in lockstep.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-9B5mY25LdMiDu+kXrVrygIvwlDpqhL5jvCQSdd0At/I=";

  # The published tarball already contains the bundled build output; there is
  # nothing for the npm build script (vite) to do, and the source it would need
  # is not shipped anyway.
  dontNpmBuild = true;

  # Actual's CLI requires Node.js v22 or higher.
  nodejs = nodejs_22;

  meta = with lib; {
    description = "Command-line interface for Actual Budget";
    homepage = "https://actualbudget.org/docs/api/cli/";
    license = licenses.mit;
    mainProgram = "actual";
    platforms = platforms.unix;
  };
}