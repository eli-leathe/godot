{
  description = "Build Godot from this checkout and provide its development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem = system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          # Godot's default build uses bundled dependencies and loads these
          # system libraries dynamically (use_sowrap=yes and use_volk=yes).
          runtimeLibraries = with pkgs; [
            alsa-lib
            dbus
            fontconfig
            libGL
            libdecor
            libpulseaudio
            libusb1
            libxkbcommon
            speechd
            systemd
            vulkan-loader
            wayland
            xorg.libX11
            xorg.libXcursor
            xorg.libXext
            xorg.libXi
            xorg.libXinerama
            xorg.libXrandr
            xorg.libXrender
          ];
          libraryPath = lib.makeLibraryPath runtimeLibraries;
          nativeTools = with pkgs; [ pkg-config python3 scons wayland-scanner ];
          godot = pkgs.stdenv.mkDerivation {
            pname = "godot-local";
            version = "checkout";
            src = lib.cleanSource self;

            nativeBuildInputs = nativeTools ++ [ pkgs.makeWrapper ];
            buildInputs = runtimeLibraries;
            dontConfigure = true;
            enableParallelBuilding = true;

            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR"
              scons -j"$NIX_BUILD_CORES" platform=linuxbsd target=editor \
                use_sowrap=yes use_volk=yes accesskit=no
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 bin/godot.linuxbsd.editor.* "$out/bin/godot"
              wrapProgram "$out/bin/godot" \
                --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg libraryPath}
              install -Dm644 icon.svg "$out/share/icons/hicolor/scalable/apps/godot.svg"
              install -Dm644 LICENSE.txt "$out/share/licenses/godot/LICENSE.txt"
              runHook postInstall
            '';

            meta = {
              description = "Godot editor built from the local source tree";
              license = lib.licenses.mit;
              platforms = systems;
              mainProgram = "godot";
            };
          };
        in {
          packages = { default = godot; inherit godot; };
          devShells.default = pkgs.mkShell {
            # clang-tools provides clangd, clang-format, and clang-tidy.
            nativeBuildInputs = nativeTools ++ [ pkgs.clang-tools ];
            buildInputs = runtimeLibraries;
            LD_LIBRARY_PATH = libraryPath;
          };
        };
    in {
      packages = forAllSystems (system: (perSystem system).packages);
      devShells = forAllSystems (system: (perSystem system).devShells);
    };
}
