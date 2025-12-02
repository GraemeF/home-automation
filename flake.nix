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
              ${pkgs.turbo}/bin/turbo prune deep-heating-server @home-automation/deep-heating-web --docker --out-dir=pruned
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
          # Web build needs patchShebangs for vite/svelte tooling
          bunDepsWeb = fetchBunDeps {
            bunNix = ./bun-deep-heating.nix;
            patchShebangs = true;
          };

          # Server build uses production deps only - no shebangs to patch
          bunDepsDeepHeating = fetchBunDeps {
            bunNix = ./bun-deep-heating.nix;
            patchShebangs = false;
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
              ${pkgs.turbo}/bin/turbo prune deep-heating-server @home-automation/deep-heating-web --docker --out-dir=pruned

              echo "Generating bun-deep-heating.nix from pruned lockfile..."
              ${bun2nix.packages.${system}.default}/bin/bun2nix \
                --lock-file pruned/bun.lock --output-file bun-deep-heating.nix
            '';

            installPhase = ''
              mkdir -p $out
              cp bun-deep-heating.nix $out/
            '';
          };

          # WEB FRONTEND BUILD
          # ===================
          # Separate derivation for SvelteKit web build - needs devDeps for vite
          # Using patchShebangs=true so vite can run in Nix sandbox
          deep-heating-web = mkDerivation {
            pname = "deep-heating-web";
            version = "0.1.0";

            src = prunedWorkspace;
            bunDeps = bunDepsWeb;
            SOURCE_DATE_EPOCH = lastModified;

            # Skip lifecycle scripts - preinstall runs "bun x only-allow bun"
            # which needs network access (not available in Nix sandbox)
            bunLifecycleScriptsPhase = ''
              echo "Skipping lifecycle scripts (no network in sandbox)"
            '';

            buildPhase = ''
              echo "Building web frontend with Turbo + Vite..."
              ${pkgs.turbo}/bin/turbo build --filter='@home-automation/deep-heating-web...'
            '';

            installPhase = ''
              echo "Installing web build to $out..."
              mkdir -p $out

              # SvelteKit adapter-bun outputs to dist/packages/deep-heating-web (see svelte.config.js)
              cp -r dist/packages/deep-heating-web/* $out/

              echo "Web build installed: $(du -sh $out | cut -f1)"
            '';
          };

          # DEEP-HEATING BUILD
          # ==================
          # Server backend build - uses production deps only (no vite/tsc)
          deep-heating = mkDerivation {
            pname = "deep-heating";
            version = "0.1.0";

            src = prunedWorkspace;
            bunDeps = bunDepsDeepHeating;
            SOURCE_DATE_EPOCH = lastModified;

            # Production-only install - no devDependencies, no shebangs to patch
            # Web frontend is built separately with full devDeps
            bunNodeModulesInstallPhase = ''
              echo "Installing production dependencies only..."
              ${pkgs.bun}/bin/bun install --frozen-lockfile --production --ignore-scripts

              echo "Normalizing timestamps to git commit time..."
              find node_modules -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} + || true
            '';

            # Skip lifecycle scripts (would fail with read-only node_modules)
            bunLifecycleScriptsPhase = ''
              echo "Skipping lifecycle scripts (read-only node_modules)"
            '';

            buildPhase = ''
              echo "Bundling server backend with Bun..."
              # Bun handles TypeScript natively - no need for turbo/tsc
              mkdir -p dist/server
              ${pkgs.bun}/bin/bun build packages/deep-heating-server/src/main.ts \
                --target=bun \
                --production \
                --outfile=dist/server/bundle.js
              echo "  Backend bundle: $(du -h dist/server/bundle.js | cut -f1)"
            '';

            installPhase = ''
              echo "Installing deep-heating to $out..."
              mkdir -p $out/bin
              mkdir -p $out/lib/deep-heating

              # Copy server backend bundle
              echo "  Copying server bundle..."
              cp -r dist/server $out/lib/deep-heating/

              # Copy pre-built web from separate derivation
              echo "  Copying web build from ${deep-heating-web}..."
              cp -r ${deep-heating-web} $out/lib/deep-heating/web

              # Create server wrapper script
              cat > $out/bin/deep-heating-server <<EOF
#!/bin/sh
exec ${pkgs.bun}/bin/bun run $out/lib/deep-heating/server/bundle.js "\$@"
EOF
              chmod +x $out/bin/deep-heating-server

              # Create web wrapper script (runs with Bun, svelte-adapter-bun output)
              cat > $out/bin/deep-heating-web <<EOF
#!/bin/sh
exec ${pkgs.bun}/bin/bun run $out/lib/deep-heating/web/index.js "\$@"
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
              # Copy config to writable location, optionally removing IP restrictions for testing
              command = ''
                cp /etc/nginx/nginx.conf /run/nginx/nginx.conf
                if [ -n "$ALLOW_ALL_IPS" ]; then
                  echo "ALLOW_ALL_IPS set - removing IP restrictions for testing"
                  ${pkgs.gnused}/bin/sed -i 's/allow  172.30.32.2;/allow all;/' /run/nginx/nginx.conf
                  ${pkgs.gnused}/bin/sed -i 's/deny   all;//' /run/nginx/nginx.conf
                fi
                ${pkgs.nginx}/bin/nginx -g "daemon off;" -c /run/nginx/nginx.conf
              '';
            };
            server = {
              env = { PORT = "3002"; };
              command = "${deep-heating}/bin/deep-heating-server";
            };
            web = {
              env = { PORT = "3001"; };
              command = "${deep-heating}/bin/deep-heating-web";
            };
          };

          # Helper to generate s6 run script content for a service
          # Multi-line commands are run directly; single commands use exec for cleaner process tree
          mkS6RunScript = def:
            let
              envLines = pkgs.lib.concatStringsSep "\n"
                (pkgs.lib.mapAttrsToList (k: v: "export ${k}=${v}") (def.env or {}));
              isMultiLine = builtins.match ".*\n.*" def.command != null;
            in ''
#!/bin/sh
exec 2>&1
${envLines}
${if isMultiLine then def.command else "exec ${def.command}"}
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
          # Combined image with nginx, server, web, and s6 supervision
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
              pkgs.gnused                 # sed for nginx config modification (ALLOW_ALL_IPS)
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
                "8099/tcp" = {};  # nginx proxy port (HA ingress default)
              };
            };
          } else null;
        in
        {
          inherit prunedWorkspace bunDepsWeb bunDepsDeepHeating bunDepsFull validateDeps generateBunNix generateBunNixDeepHeating deep-heating-web deep-heating;
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
