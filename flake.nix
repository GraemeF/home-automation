{
  description = "Deep Heating - Gleam-based smart heating control";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # beads: Git-based issue tracker designed for AI coding workflows
    beads = {
      url = "github:steveyegge/beads/v0.43.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, beads }:
    let
      # Multi-architecture support
      systems = nixpkgs.lib.systems.flakeExposed;
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Git commit timestamp for reproducible builds
          lastModified = builtins.toString (self.lastModified or 1);

          # GLEAM BUILD
          # ===========
          # Gleam-based Deep Heating using OTP actors

          # Filtered source for Gleam project only
          gleamSrc = pkgs.lib.cleanSourceWith {
            src = ./packages/deep_heating;
            filter = path: type:
              let
                baseName = baseNameOf path;
                relPath = pkgs.lib.removePrefix (toString ./packages/deep_heating + "/") (toString path);
              in
              !(
                pkgs.lib.hasPrefix "build" relPath
                || pkgs.lib.hasPrefix ".git" relPath
                || baseName == "result"
              );
          };

          # Hash of manifest.toml - invalidates cache when deps change
          gleamManifestHash = builtins.substring 0 8 (builtins.hashFile "sha256" ./packages/deep_heating/manifest.toml);

          # Fixed-Output Derivation for Gleam dependencies
          # Downloads deps from Hex and caches them reproducibly
          gleamDeps = pkgs.stdenv.mkDerivation {
            pname = "deep-heating-gleam-deps-${gleamManifestHash}";
            version = "0.1.0";

            src = gleamSrc;
            nativeBuildInputs = [ pkgs.gleam pkgs.cacert ];

            # FOD settings - allows network access during build
            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            # To update: run `nix build .#gleamDeps` and use the hash from the error
            outputHash = "sha256-wya1eCIxjl5gcvC05BEsbeFdsQBXSs6+kVT4K1ZfHPg=";

            buildPhase = ''
              export HOME=$TMPDIR
              export HEX_HOME=$TMPDIR/.hex
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              gleam deps download
            '';

            installPhase = ''
              mkdir -p $out
              cp -r build/packages/* $out/

              # Sort packages.toml for reproducibility
              if [ -f $out/packages.toml ]; then
                head -1 $out/packages.toml > $out/packages.toml.sorted
                tail -n +2 $out/packages.toml | sort >> $out/packages.toml.sorted
                mv $out/packages.toml.sorted $out/packages.toml
              fi
            '';
          };

          # Tailwind CSS standalone executable (no Node.js required)
          # Version pinned for reproducibility - update hash when changing version
          tailwindVersion = "4.1.8";
          tailwindStandalone = pkgs.fetchurl {
            url = "https://github.com/tailwindlabs/tailwindcss/releases/download/v${tailwindVersion}/tailwindcss-${
              if pkgs.stdenv.hostPlatform.isDarwin then
                if pkgs.stdenv.hostPlatform.isAarch64 then "macos-arm64" else "macos-x64"
              else
                if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64"
            }";
            sha256 = if pkgs.stdenv.hostPlatform.isDarwin then
              if pkgs.stdenv.hostPlatform.isAarch64 then
                "sha256-GeUnkdNW3VnbaCdK42pYebqwzp2sI8x7Dxn8e3wdN6I="
              else
                "sha256-SmyyYNdcS9ygck+8w7I6WttScVrW14WVRjyGEoyhwyk="
            else
              if pkgs.stdenv.hostPlatform.isAarch64 then
                "sha256-KKd9Hlmw5FtBaDweOUdiH9/nP2iVsF23w09j8/SJjo0="
              else
                "sha256-j4TOgQvf8iXlmXgdHi2qgrQoIikCHIZ6cbQZ9Z+aqDY=";
          };

          # DaisyUI bundle for Tailwind standalone
          # Version pinned for reproducibility - update hash when changing version
          daisyuiVersion = "5.0.14";
          daisyuiBundle = pkgs.fetchurl {
            url = "https://github.com/saadeghi/daisyui/releases/download/v${daisyuiVersion}/daisyui.mjs";
            sha256 = "sha256-Gl5g0d7bEof8cM5k4qhaEKvViErdEGwNKyO4PrtPTdg=";
          };

          # Build Tailwind CSS with DaisyUI
          tailwindCss = pkgs.stdenv.mkDerivation {
            pname = "deep-heating-css";
            version = "0.1.0";

            src = gleamSrc;

            buildPhase = ''
              # Set up the CSS build environment
              mkdir -p src/styles
              cp ${daisyuiBundle} src/styles/daisyui.mjs
              cp ${tailwindStandalone} ./tailwindcss
              chmod +x ./tailwindcss

              # Run Tailwind CLI to build CSS
              ./tailwindcss -i ./src/styles/input.css -o ./styles.css --minify
            '';

            installPhase = ''
              mkdir -p $out
              cp styles.css $out/
            '';
          };

          # Main Gleam build - produces Erlang shipment
          deep-heating = pkgs.stdenv.mkDerivation {
            pname = "deep-heating";
            version = "0.1.0";

            src = gleamSrc;
            nativeBuildInputs = [ pkgs.gleam pkgs.erlang_28 pkgs.rebar3 ];

            SOURCE_DATE_EPOCH = lastModified;

            buildPhase = ''
              # Copy in the cached dependencies (need writable copies)
              mkdir -p build/packages
              cp -r ${gleamDeps}/* build/packages/
              chmod -R u+w build/packages/

              # Copy compiled CSS to priv directory
              mkdir -p priv/static
              cp ${tailwindCss}/styles.css priv/static/

              # Build the Erlang release
              gleam export erlang-shipment
            '';

            installPhase = ''
              mkdir -p $out/lib/deep-heating
              cp -r build/erlang-shipment/* $out/lib/deep-heating/

              # Create wrapper script
              mkdir -p $out/bin
              cat > $out/bin/deep-heating <<EOF
#!/bin/sh
exec $out/lib/deep-heating/entrypoint.sh run "\$@"
EOF
              chmod +x $out/bin/deep-heating

              echo "Installation complete!"
              echo "  Size: $(du -sh $out | cut -f1)"
            '';

            meta = with pkgs.lib; {
              description = "Deep Heating - TRV control with OTP actors";
              homepage = "https://github.com/GraemeF/home-automation";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          # DOCKER IMAGE (Linux only)
          # =========================
          # Simplified image - Gleam OTP app serves everything (no nginx needed)
          # Uses PORT env var for configurable port (default 8085, but HA uses 8099)
          dockerImage = if pkgs.stdenv.isLinux then pkgs.dockerTools.buildLayeredImage {
            name = "deep-heating";
            tag = "nix-build";

            # Set timestamps to git commit time for reproducibility
            created = "@${lastModified}";
            mtime = "@${lastModified}";

            # Minimal image contents - just the OTP release and shell
            contents = [
              deep-heating                # OTP release with entrypoint
              pkgs.dockerTools.binSh      # /bin/sh for entrypoint script
              pkgs.coreutils              # Basic utilities (needed for entrypoint.sh)
            ];

            # OCI/Docker configuration
            config = {
              Entrypoint = [ "${deep-heating}/bin/deep-heating" ];

              WorkingDir = "/app";

              Env = [
                # HA ingress port - the Gleam server reads PORT env var
                "PORT=8099"
                # These are set by HA addon config, defaults here for standalone testing
                "HOME_CONFIG_PATH=/data/home.json"
              ];

              ExposedPorts = {
                "8099/tcp" = {};  # HA ingress default port
              };
            };
          } else null;
        in
        {
          # Gleam packages
          inherit gleamDeps deep-heating tailwindCss;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          # Linux-only packages
          inherit dockerImage;
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Get the correct Tailwind standalone for this platform
          tailwindPlatform = if pkgs.stdenv.hostPlatform.isDarwin then
            if pkgs.stdenv.hostPlatform.isAarch64 then "macos-arm64" else "macos-x64"
          else
            if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";

          # Script to set up local CSS development
          setupCssScript = pkgs.writeShellScriptBin "setup-css" ''
            set -e
            cd packages/deep_heating/src/styles

            # Download Tailwind standalone if not present
            if [ ! -f tailwindcss ]; then
              echo "Downloading Tailwind CSS v4.1.8 (${tailwindPlatform})..."
              curl -sL "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.8/tailwindcss-${tailwindPlatform}" -o tailwindcss
              chmod +x tailwindcss
            fi

            # Download DaisyUI bundle if not present
            if [ ! -f daisyui.mjs ]; then
              echo "Downloading DaisyUI v5.0.14..."
              curl -sL "https://github.com/saadeghi/daisyui/releases/download/v5.0.14/daisyui.mjs" -o daisyui.mjs
            fi

            echo "CSS dev environment ready!"
            echo "Run 'build-css' to compile, or 'build-css --watch' for watch mode"
          '';

          # Script to build CSS
          buildCssScript = pkgs.writeShellScriptBin "build-css" ''
            cd packages/deep_heating/src/styles
            if [ ! -f tailwindcss ]; then
              echo "Error: Run 'setup-css' first to download Tailwind CLI"
              exit 1
            fi
            ./tailwindcss -i input.css -o ../../priv/static/styles.css --minify "$@"
          '';
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.git
              pkgs.docker
              pkgs.pre-commit # Git hooks framework
              pkgs.curl       # For downloading CSS dependencies
              beads.packages.${system}.default  # bd CLI for beads issue tracker

              # Gleam toolchain
              pkgs.gleam
              pkgs.erlang_28  # OTP 28 for BEAM runtime
              pkgs.rebar3     # Erlang build tool (uses nixpkgs default OTP 28)

              # CSS development scripts
              setupCssScript
              buildCssScript
            ];

            shellHook = ''
              echo "Deep Heating development environment loaded!"
              echo "Gleam version: $(gleam --version)"
              echo "Erlang/OTP version: $(erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().')"
              echo "System: ${system}"
              echo ""
              echo "Available commands:"
              echo "  gleam build      - Build the project"
              echo "  gleam test       - Run tests"
              echo "  gleam run        - Run the project"
              echo "  setup-css        - Download Tailwind/DaisyUI for local CSS development"
              echo "  build-css        - Build CSS (add --watch for watch mode)"

              # Install pre-commit hooks
              pre-commit install --allow-missing-config 2>/dev/null || true
            '';
          };
        }
      );

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Gleam format check - validates code is formatted
          # Note: gleam build requires network for deps, use pre-commit instead
          format = pkgs.runCommand "gleam-format-check" {
            buildInputs = [ pkgs.gleam ];
            src = ./packages/deep_heating;
          } ''
            cd $src
            gleam format --check src test && touch $out
          '';
        }
      );
    };
}
