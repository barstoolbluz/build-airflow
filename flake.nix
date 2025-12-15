{
  description = "Apache Airflow (3.1.3, 3.1.1, 2.11.0, 2.10.5) with Kubernetes support - Multi-version builds via Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # ============================================================================
        # AIRFLOW VERSION METADATA
        # ============================================================================
        # All supported Airflow versions with their metadata
        versions = {
          "3.1.3" = {
            python = "3.12";
            k8sProvider = "10.9.0";
            releaseDate = "2025-11-14";
            support = "Active Support";
            pythonVersions = "3.9, 3.10, 3.11, 3.12, 3.13";
            recommended = true;
          };
          "3.1.1" = {
            python = "3.11";
            k8sProvider = "10.8.2";
            releaseDate = "2025-10-27";
            support = "Active Support";
            pythonVersions = "3.9, 3.10, 3.11, 3.12";
            recommended = false;
          };
          "2.11.0" = {
            python = "3.11";
            k8sProvider = "10.5.0";
            releaseDate = "2025-05-20";
            support = "Limited Support until April 2026";
            pythonVersions = "3.9, 3.10, 3.11, 3.12 (NO Python 3.8!)";
            recommended = false;
          };
          "2.10.5" = {
            python = "3.11";
            k8sProvider = "8.4.x";
            releaseDate = "2025-02-06";
            support = "Limited Support until April 2026";
            pythonVersions = "3.8, 3.9, 3.10, 3.11, 3.12";
            recommended = false;
          };
        };

        # ============================================================================
        # VERSION SELECTION (Hybrid Approach)
        # ============================================================================
        # Three ways to select version:
        #   1. Default: Uses 3.1.3 (no action needed)
        #   2. Environment variable: AIRFLOW_VERSION=2.11.0 nix build --impure .#airflow
        #   3. Named output: nix build --impure .#airflow-2-11-0
        # ============================================================================

        # Check environment variable, fallback to default
        envAirflowVersion = builtins.getEnv "AIRFLOW_VERSION";
        defaultVersion = "3.1.3";
        selectedVersion = if envAirflowVersion != "" then envAirflowVersion else defaultVersion;

        # Validate version exists
        versionExists = builtins.hasAttr selectedVersion versions;
        _ = if !versionExists && envAirflowVersion != "" then
          throw "Invalid AIRFLOW_VERSION '${selectedVersion}'. Supported versions: ${builtins.concatStringsSep ", " (builtins.attrNames versions)}"
        else null;

        # Get metadata for selected version
        versionMeta = versions.${selectedVersion};
        pythonVersion = versionMeta.python;

        # Select Python package based on version
        python = if pythonVersion == "3.11" then pkgs.python311
                 else if pythonVersion == "3.10" then pkgs.python310
                 else if pythonVersion == "3.9" then pkgs.python39
                 else if pythonVersion == "3.8" then pkgs.python38
                 else if pythonVersion == "3.12" then pkgs.python312
                 else if pythonVersion == "3.13" then pkgs.python313
                 else pkgs.python312;

        # ============================================================================
        # BUILD FUNCTION FACTORY
        # ============================================================================
        # Creates an Airflow build with specified version and providers
        mkAirflow = airflowVersion: buildType:
          let
            versionMeta = versions.${airflowVersion};
            pythonVer = versionMeta.python;
            pythonPkg = if pythonVer == "3.11" then pkgs.python311
                        else if pythonVer == "3.10" then pkgs.python310
                        else if pythonVer == "3.9" then pkgs.python39
                        else if pythonVer == "3.8" then pkgs.python38
                        else if pythonVer == "3.12" then pkgs.python312
                        else if pythonVer == "3.13" then pkgs.python313
                        else pkgs.python312;
            constraintUrl = "https://raw.githubusercontent.com/apache/airflow/constraints-${airflowVersion}/constraints-${pythonVer}.txt";

            # Provider extras based on build type
            providerExtras = if buildType == "full"
              then "cncf.kubernetes,postgres,redis,http,ssh"
              else "cncf.kubernetes";

            pname = if buildType == "full" then "apache-airflow-full" else "apache-airflow";
          in
          pkgs.stdenv.mkDerivation {
            pname = pname;
            version = airflowVersion;

            # Minimal source - we install from PyPI
            src = pkgs.writeTextFile {
              name = "${pname}-build-script";
              text = "# Airflow ${airflowVersion} build placeholder";
            };

            nativeBuildInputs = [
              pythonPkg
              pkgs.curl
              pkgs.cacert
            ];

            buildInputs = [
              pythonPkg
              pkgs.postgresql
              pkgs.redis
            ];

            # This build requires network access for pip downloads
            __noChroot = true;

            buildPhase = ''
              echo "========================================="
              echo "Building ${pname} ${airflowVersion}"
              echo "Build type: ${buildType}"
              echo "Python: ${pythonVer}"
              echo "========================================="

              # Create virtualenv in $out
              ${pythonPkg}/bin/python -m venv $out
              source $out/bin/activate

              # Upgrade pip and build tools
              pip install --upgrade pip setuptools wheel

              # Download constraint file
              echo "Downloading constraints from:"
              echo "  ${constraintUrl}"
              curl -sSL "${constraintUrl}" -o constraints.txt

              # Install Airflow with providers
              echo ""
              echo "Installing apache-airflow[${providerExtras}]==${airflowVersion}..."
              pip install "apache-airflow[${providerExtras}]==${airflowVersion}" \
                --constraint constraints.txt

              # Verify installation
              echo ""
              echo "========================================="
              echo "✅ Installation complete!"
              echo "========================================="
              airflow version
              echo ""
              echo "Provider verification:"
              python -c "from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator; print('  ✅ KubernetesPodOperator: OK')"
              echo ""

              # Cleanup
              rm -f constraints.txt
            '';

            installPhase = ''
              echo "Virtualenv created in $out"
            '';

            dontStrip = true;
            dontPatchELF = true;
            dontPatchShebangs = false;

            meta = with pkgs.lib; {
              description = "Apache Airflow ${airflowVersion} - Workflow orchestration platform";
              longDescription = ''
                Apache Airflow ${airflowVersion} with ${if buildType == "full" then "multiple providers" else "Kubernetes provider"}.
                Built via pip in a virtualenv.

                IMPORTANT: Requires --impure flag for network access:
                  nix build --impure .#${pname}

                Support Status: ${versionMeta.support}
                Python Versions: ${versionMeta.pythonVersions}
                K8s Provider: ${versionMeta.k8sProvider}
              '';
              homepage = "https://airflow.apache.org";
              license = licenses.asl20;
              platforms = platforms.unix;
            };
          };

      in {
        # ============================================================================
        # PACKAGE OUTPUTS
        # ============================================================================
        packages = {
          # Dynamic outputs (respect $AIRFLOW_VERSION environment variable)
          default = mkAirflow selectedVersion "basic";
          airflow = mkAirflow selectedVersion "basic";
          airflow-full = mkAirflow selectedVersion "full";

          # Named outputs for explicit version selection
          # Airflow 3.1.3
          airflow-3-1-3 = mkAirflow "3.1.3" "basic";
          airflow-full-3-1-3 = mkAirflow "3.1.3" "full";

          # Airflow 3.1.1
          airflow-3-1-1 = mkAirflow "3.1.1" "basic";
          airflow-full-3-1-1 = mkAirflow "3.1.1" "full";

          # Airflow 2.11.0
          airflow-2-11-0 = mkAirflow "2.11.0" "basic";
          airflow-full-2-11-0 = mkAirflow "2.11.0" "full";

          # Airflow 2.10.5
          airflow-2-10-5 = mkAirflow "2.10.5" "basic";
          airflow-full-2-10-5 = mkAirflow "2.10.5" "full";
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = [
            python
            pkgs.postgresql
            pkgs.redis
            pkgs.kubectl
            pkgs.kind
            pkgs.git
            pkgs.curl
          ];

          shellHook = ''
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║   Apache Airflow Development Environment              ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo ""
            echo "Active Configuration:"
            echo "  Airflow Version: ${selectedVersion} ${if versionMeta.recommended then "⭐" else ""}"
            echo "  Python Version: ${pythonVersion}"
            echo "  Support: ${versionMeta.support}"
            echo ""
            echo "Supported Versions:"
            echo "  3.1.3  - Latest (Active Support) ⭐"
            echo "  3.1.1  - Previous stable (Active Support)"
            echo "  2.11.0 - Latest 2.x (Limited Support, Python 3.9+)"
            echo "  2.10.5 - Python 3.8 support (Limited Support)"
            echo ""
            echo "Build Options (3 ways to select version):"
            echo ""
            echo "  1. Default (${defaultVersion}):"
            echo "     nix build --impure .#airflow"
            echo ""
            echo "  2. Environment variable:"
            echo "     AIRFLOW_VERSION=2.11.0 nix build --impure .#airflow"
            echo "     AIRFLOW_VERSION=2.10.5 nix build --impure .#airflow-full"
            echo ""
            echo "  3. Named outputs:"
            echo "     nix build --impure .#airflow-3-1-3"
            echo "     nix build --impure .#airflow-3-1-1"
            echo "     nix build --impure .#airflow-2-11-0"
            echo "     nix build --impure .#airflow-2-10-5"
            echo "     nix build --impure .#airflow-full-3-1-3"
            echo ""
            echo "List all outputs:"
            echo "  nix flake show"
            echo ""
            echo "Use built Airflow:"
            echo "  ./result/bin/airflow version"
            echo "  source result/bin/activate"
            echo ""
            echo "📖 See BUILDING.md for detailed build instructions"
            echo ""
          '';
        };

        # Apps - for direct execution
        apps = {
          default = {
            type = "app";
            program = "${mkAirflow selectedVersion "basic"}/bin/airflow";
          };
          airflow = {
            type = "app";
            program = "${mkAirflow selectedVersion "basic"}/bin/airflow";
          };
        };
      }
    );
}
