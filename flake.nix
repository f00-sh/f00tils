# Nix flake for f00tils — pure assembly multicall (Linux x86-64).
{
  description = "f00tils — pure freestanding assembly GNU coreutils replacement suite";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        isLinuxX64 = system == "x86_64-linux";
      in {
        packages.default = if !isLinuxX64 then
          throw "f00tils freestanding ASM currently targets x86_64-linux only"
        else
          pkgs.stdenv.mkDerivation {
            pname = "f00";
            version = "0.16.7";
            src = ./.;
            nativeBuildInputs = [ pkgs.nasm pkgs.binutils pkgs.gnumake ];
            buildPhase = ''
              make -C asm -j$NIX_BUILD_CORES
            '';
            installPhase = ''
              mkdir -p $out/bin $out/share/man/man1
              install -m755 asm/f00 $out/bin/f00
              while IFS= read -r link; do
                name=$(basename "$link")
                ln -s f00 "$out/bin/$name"
              done < <(find asm -maxdepth 1 -type l -name 'f00-*' | sort)
              if [ -d asm/man/man1 ]; then
                cp -a asm/man/man1/f00*.1 $out/share/man/man1/ || true
              fi
            '';
            meta = with pkgs.lib; {
              description = "f00tils — pure assembly GNU coreutils replacement suite (multicall)";
              homepage = "https://f00.sh";
              license = licenses.mit;
              platforms = [ "x86_64-linux" ];
              mainProgram = "f00";
            };
          };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/f00";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nasm binutils gnumake python3 ];
        };
      });
}
