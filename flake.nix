# srs as a yen repo (github:vic/yen): `nix develop` = numtide/devshell, its menu lists the srs commands.
# CI runs the same commands: .github/workflows/ci.yml is generated, `nix run .#write-files`.
{
  description = "srs: a Scala3-like language with flow-typed effects, self-hosted on portable C";

  outputs =
    inputs:
    inputs.yen.lib.mkFlake {
      inherit inputs;
      inherit (inputs.nixpkgs) lib;
    } (inputs.import-tree ./nix);

  inputs = {
    yen.url = "github:vic/yen";
    import-tree.url = "github:denful/import-tree";
    nixpkgs.url = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz"; # zig 0.17
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    files.url = "github:sini/files";
  };
}
