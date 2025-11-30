{
  description = "Deep Heating monorepo - Nix flake for reproducible builds";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    bun2nix = {
      url = "github:baileyluTCD/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, bun2nix }:
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

          # Paths to exclude from source filtering (build outputs, metadata, etc.)
          excludedPathPrefixes = [ "node_modules" ".git" "result" ".beads" ];
          excludedFileNames = [ ".turbo" ];

          # Filtered source - exclude build outputs and metadata
          depSource = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let
                baseName = baseNameOf path;
                relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
                hasExcludedPrefix = builtins.any (prefix: pkgs.lib.hasPrefix prefix relPath) excludedPathPrefixes;
                hasExcludedName = builtins.elem baseName excludedFileNames;
              in
              !(hasExcludedPrefix || hasExcludedName);
          };

          # Pruned workspace - only packages needed for deep-heating apps
          # Turbo prune analyzes the monorepo dependency graph and copies only required packages
          prunedWorkspace = pkgs.stdenv.mkDerivation {
            pname = "deep-heating-pruned-workspace";
            version = "0.1.0";

            src = depSource;
            buildInputs = [ pkgs.turbo ];

            buildPhase = ''
              echo "Pruning workspace with turbo..."
              ${pkgs.turbo}/bin/turbo prune deep-heating-socketio @home-automation/deep-heating-web --docker --out-dir=pruned
            '';

            installPhase = ''
              echo "Saving pruned workspace to $out..."
              mkdir -p $out
              # Copy the pruned workspace (without node_modules - deps installed later)
              cp -r pruned/full/* $out/

              # turbo prune --docker creates pruned lockfile at pruned/bun.lock (root level)
              # NOT in pruned/full/ - see https://turborepo.com/repo/docs/reference/prune
              echo "Copying pruned bun.lock from turbo prune output..."
              cp pruned/bun.lock $out/

              # Copy root config files not included by turbo prune
              echo "Copying root config files..."
              cp tsconfig.base.json $out/ || true

              echo "Pruned workspace created with:"
              echo "  - $(find $out -name package.json | wc -l) package.json files"
              echo "  - bun.lock (pruned lockfile from turbo)"
            '';
          };

          # BUN2NIX DEPENDENCY MANAGEMENT
          # ==============================
          # Access bun2nix v2 functions for this system
          inherit (bun2nix.packages.${system}.default) mkDerivation fetchBunDeps;

          # Fetch Bun dependencies from pruned lockfile (for builds)
          # patchShebangs = true required on Linux for tools like tsc to work in sandbox
          bunDepsDeepHeating = fetchBunDeps {
            bunNix = ./bun-deep-heating.nix;
            patchShebangs = true;
          };

          # Fetch Bun dependencies from full lockfile (for CI validation)
          # Validates that all packages in the monorepo resolve correctly
          bunDepsFull = fetchBunDeps {
            bunNix = ./bun.nix;
            patchShebangs = false;
          };

          # CI validation derivation - validates full lockfile deps resolve
          validateDeps = pkgs.stdenv.mkDerivation {
            pname = "validate-deps";
            version = "0.1.0";
            dontUnpack = true;

            buildPhase = ''
              echo "Validating full lockfile dependencies..."
              echo "  bunDepsFull: ${bunDepsFull}"
              echo "Full lockfile dependencies resolved successfully"
            '';

            installPhase = ''
              mkdir -p $out
              echo "validated" > $out/result
            '';
          };

          # BUN.NIX GENERATORS (for CI regeneration)
          # =========================================
          generateBunNix = pkgs.stdenv.mkDerivation {
            pname = "generate-bun-nix";
            version = "0.1.0";
            src = depSource;

            buildPhase = ''
              echo "Generating bun.nix from full lockfile..."
              ${bun2nix.packages.${system}.default}/bin/bun2nix \
                --lock-file bun.lock --output-file bun.nix
            '';

            installPhase = ''
              mkdir -p $out
              cp bun.nix $out/
            '';
          };

          generateBunNixDeepHeating = pkgs.stdenv.mkDerivation {
            pname = "generate-bun-nix-deep-heating";
            version = "0.1.0";
            src = depSource;
            buildInputs = [ pkgs.turbo ];

            buildPhase = ''
              echo "Pruning workspace with turbo..."
              ${pkgs.turbo}/bin/turbo prune deep-heating-socketio @home-automation/deep-heating-web --docker --out-dir=pruned

              echo "Generating bun-deep-heating.nix from pruned lockfile..."
              ${bun2nix.packages.${system}.default}/bin/bun2nix \
                --lock-file pruned/bun.lock --output-file bun-deep-heating.nix
            '';

            installPhase = ''
              mkdir -p $out
              cp bun-deep-heating.nix $out/
            '';
          };

          # DEEP-HEATING BUILD
          # ==================
          # Combined build of socketio backend and SvelteKit web frontend
          deep-heating = mkDerivation {
            pname = "deep-heating";
            version = "0.1.0";

            src = prunedWorkspace;
            bunDeps = bunDepsDeepHeating;
            SOURCE_DATE_EPOCH = lastModified;

            # Override bun install to use hoisted linker
            # NOTE: Not using --production because build requires devDependencies (tsc, vite)
            bunNodeModulesInstallPhase = ''
              echo "Installing node modules with hoisted linker..."
              ${pkgs.bun}/bin/bun install --frozen-lockfile --linker=hoisted --ignore-scripts

              echo "Normalizing timestamps to git commit time..."
              find node_modules -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} + || true
            '';

            # Skip lifecycle scripts (would fail with read-only node_modules)
            bunLifecycleScriptsPhase = ''
              echo "Skipping lifecycle scripts (read-only node_modules)"
            '';

            buildPhase = ''
              echo "Building deep-heating with Turbo..."
              # Build both socketio and web (SvelteKit)
              ${pkgs.turbo}/bin/turbo build --filter='deep-heating-socketio...' --filter='@home-automation/deep-heating-web...'

              echo "Bundling socketio backend with Bun..."
              mkdir -p dist/socketio
              ${pkgs.bun}/bin/bun build packages/deep-heating-socketio/src/main.ts \
                --target=bun \
                --production \
                --outfile=dist/socketio/bundle.js
              echo "  Backend bundle: $(du -h dist/socketio/bundle.js | cut -f1)"

              echo "SvelteKit build output:"
              ls -la dist/packages/deep-heating-web/ || echo "  (build output location may differ)"
            '';

            installPhase = ''
              echo "Installing deep-heating to $out..."
              mkdir -p $out/bin
              mkdir -p $out/lib/deep-heating

              # Copy socketio backend bundle
              echo "  Copying socketio bundle..."
              cp -r dist/socketio $out/lib/deep-heating/

              # Copy SvelteKit web build
              echo "  Copying web build..."
              cp -r dist/packages/deep-heating-web $out/lib/deep-heating/web

              # Create socketio wrapper script
              cat > $out/bin/deep-heating-socketio <<EOF
#!/bin/sh
exec ${pkgs.bun}/bin/bun run $out/lib/deep-heating/socketio/bundle.js "\$@"
EOF
              chmod +x $out/bin/deep-heating-socketio

              # Create web wrapper script (runs with Node, adapter-node output)
              cat > $out/bin/deep-heating-web <<EOF
#!/bin/sh
exec ${pkgs.nodejs}/bin/node $out/lib/deep-heating/web/index.js "\$@"
EOF
              chmod +x $out/bin/deep-heating-web

              echo "Installation complete!"
              echo "  Size: $(du -sh $out | cut -f1)"
            '';

            meta = with pkgs.lib; {
              description = "Smart heating control with TRV and external sensor integration";
              homepage = "https://github.com/GraemeF/home-automation";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          # S6 SERVICE CONFIGURATION (using raw s6 from nixpkgs)
          # ===================================================
          # s6-svscan expects a scandir with service subdirectories.
          # Each service directory contains a 'run' script.
          # The scandir must be writable at runtime, so we store definitions
          # in /etc/s6/services and copy to /run/service at container start.
          #
          # Reference: https://skarnet.org/software/s6/servicedir.html

          # Service definitions - data structure for s6 services
          # Each service has: command (required), env (optional map)
          s6ServiceDefs = {
            nginx = {
              command = ''${pkgs.nginx}/bin/nginx -g "daemon off;" -c /etc/nginx/nginx.conf'';
            };
            socketio = {
              env = { PORT = "3002"; };
              command = "${deep-heating}/bin/deep-heating-socketio";
            };
            web = {
              env = { PORT = "3001"; };
              command = "${deep-heating}/bin/deep-heating-web";
            };
          };

          # Helper to generate s6 run script content for a service
          mkS6RunScript = def:
            let
              envLines = pkgs.lib.concatStringsSep "\n"
                (pkgs.lib.mapAttrsToList (k: v: "export ${k}=${v}") (def.env or {}));
            in ''
#!/bin/sh
exec 2>&1
${envLines}
exec ${def.command}
'';

          # Helper to generate install commands for a service directory
          mkS6ServiceInstall = name: def: ''
              mkdir -p $out/etc/s6/services/${name}
              cat > $out/etc/s6/services/${name}/run <<'RUNSCRIPT'
${mkS6RunScript def}RUNSCRIPT
              chmod +x $out/etc/s6/services/${name}/run
          '';

          s6Services = pkgs.stdenv.mkDerivation {
            pname = "deep-heating-s6-services";
            version = "0.1.0";
            dontUnpack = true;

            installPhase = ''
              echo "Creating s6 service definitions..."
              mkdir -p $out/etc/s6/services

              ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList mkS6ServiceInstall s6ServiceDefs)}

              echo "s6 services created in /etc/s6/services:"
              ${pkgs.lib.concatStringsSep "\n" (map (name: ''echo "  - ${name}"'') (builtins.attrNames s6ServiceDefs))}
            '';
          };

          # CONTAINER INIT SCRIPT
          # =====================
          # Copies service definitions to writable /run/service and execs s6-svscan
          containerInit = pkgs.writeShellScript "container-init" ''
            set -e

            echo "Deep Heating container starting..."

            # Create writable scandir
            mkdir -p /run/service

            # Copy service definitions (need writable supervise/ subdirs)
            cp -r /etc/s6/services/* /run/service/

            # Create required directories for nginx and system
            mkdir -p /run/nginx /var/log/nginx /var/cache/nginx /tmp

            echo "Starting s6-svscan..."
            exec ${pkgs.s6}/bin/s6-svscan /run/service
          '';

          # NGINX CONFIGURATION
          # ===================
          # Copy nginx config from the source tree, adding user directive for container
          nginxConfig = pkgs.stdenv.mkDerivation {
            pname = "deep-heating-nginx-config";
            version = "0.1.0";
            src = ./packages/deep-heating/assets;

            installPhase = ''
              mkdir -p $out/etc/nginx
              # Prepend user directive (fakeNss provides nobody:nobody)
              echo "user nobody nobody;" > $out/etc/nginx/nginx.conf
              cat ingress.conf >> $out/etc/nginx/nginx.conf
              echo "Nginx config installed to $out/etc/nginx/nginx.conf"
            '';
          };

          # DOCKER IMAGE (Linux only)
          # =========================
          # Combined image with nginx, socketio, web, and s6 supervision
          dockerImage = if pkgs.stdenv.isLinux then pkgs.dockerTools.buildLayeredImage {
            name = "deep-heating";
            tag = "latest";

            # Set timestamps to git commit time for reproducibility
            created = "@${lastModified}";
            mtime = "@${lastModified}";

            # Image contents
            contents = [
              deep-heating                # Application binaries and bundles
              pkgs.nginx                  # Web server for proxying
              pkgs.s6                     # Supervision suite (from nixpkgs)
              s6Services                  # Our service definitions
              nginxConfig                 # Nginx configuration
              pkgs.dockerTools.binSh      # /bin/sh for scripts
              pkgs.dockerTools.fakeNss    # Provides /etc/passwd and /etc/group (for nginx)
              pkgs.coreutils              # Basic utilities (cp, mkdir, etc)
            ];

            # OCI/Docker configuration
            config = {
              # Our init script sets up scandir and execs s6-svscan
              Entrypoint = [ "${containerInit}" ];

              WorkingDir = "/app";

              Env = [
                "NODE_ENV=production"
              ];

              ExposedPorts = {
                "8503/tcp" = {};  # nginx proxy port (from ingress.conf)
              };
            };
          } else null;
        in
        {
          inherit prunedWorkspace bunDepsDeepHeating bunDepsFull validateDeps generateBunNix generateBunNixDeepHeating deep-heating;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          # Linux-only packages
          inherit s6Services nginxConfig containerInit dockerImage;
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              bun
              git
              docker
            ];

            shellHook = ''
              echo "Deep Heating development environment loaded!"
              echo "Bun version: $(bun --version)"
              echo "System: ${system}"
              echo ""
              echo "Available commands:"
              echo "  bun run build    - Build all packages"
              echo "  bun run test     - Run all tests"
              echo "  bun run dev      - Start dev servers"
            '';
          };
        }
      );
    };
}
