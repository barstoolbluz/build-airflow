{ stdenv
, lib
, python311
, curl
, cacert
, gcc-unwrapped
}:

let
  # ===========================================================================
  # USER CONFIGURATION - Edit these values
  # ===========================================================================
  version = "3.1.1";           # Airflow version to build
  pythonVersion = "3.11";      # Python version for constraint file URL

  # Version metadata for reference
  versionInfo = {
    "3.1.1" = {
      pythonVersions = "3.9, 3.10, 3.11, 3.12";
      support = "Active Support";
      k8sProvider = "10.8.2";
    };
    "2.11.0" = {
      pythonVersions = "3.9, 3.10, 3.11, 3.12";
      support = "Limited Support until April 2026";
      k8sProvider = "10.5.0";
    };
    "2.10.5" = {
      pythonVersions = "3.8, 3.9, 3.10, 3.11, 3.12";
      support = "Limited Support until April 2026";
      k8sProvider = "8.4.x";
    };
  };

  # ===========================================================================
  # Build Configuration (DO NOT EDIT below this line unless you know what you're doing)
  # ===========================================================================

  # Use python311 from manifest (python3 = 3.13 has no grpcio wheels)
  pythonPkg = python311;

  # Construct constraint URL
  constraintUrl = "https://raw.githubusercontent.com/apache/airflow/constraints-${version}/constraints-${pythonVersion}.txt";

  # Get version metadata
  meta = versionInfo.${version} or {
    pythonVersions = "Unknown";
    support = "Unknown";
    k8sProvider = "N/A";
  };

in
stdenv.mkDerivation {
  pname = "apache-airflow-minimal";
  inherit version;

  # Placeholder source (we install from PyPI)
  src = builtins.toFile "placeholder" "# Airflow ${version} minimal build";

  nativeBuildInputs = [
    pythonPkg
    curl
    cacert
  ];

  buildInputs = [
    pythonPkg
  ] ++ lib.optionals stdenv.isLinux [
    gcc-unwrapped  # For libstdc++.so.6 (Airflow 2.x re2 package)
  ];

  # Network access required for pip
  __noChroot = true;

  # Skip unpack phase (we don't have source to unpack)
  unpackPhase = ":";

  buildPhase = ''
    echo "========================================="
    echo "Building Apache Airflow (Minimal)"
    echo "Version: ${version}"
    echo "Python: ${pythonVersion}"
    echo "Support: ${meta.support}"
    echo "========================================="

    # Create virtualenv in $out
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    # Upgrade pip
    pip install --upgrade pip setuptools wheel

    # Download constraint file
    echo "Downloading constraints from:"
    echo "  ${constraintUrl}"
    curl -sSL "${constraintUrl}" -o constraints.txt

    # Install Airflow (no extras)
    echo ""
    echo "Installing apache-airflow==${version} (no providers)..."
    pip install "apache-airflow==${version}" \
      --constraint constraints.txt

    # Verify installation
    echo ""
    echo "========================================="
    echo "✅ Installation complete!"
    echo "========================================="
    echo "Airflow ${version} installed successfully (minimal variant)"
    echo "Variant: Minimal (LocalExecutor only)"

    # Cleanup
    rm -f constraints.txt
  '';

  installPhase = ''
    echo "Virtualenv created in $out"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "Apache Airflow ${version} - Minimal installation (no providers)";
    longDescription = ''
      Apache Airflow ${version} with no extra providers.
      LocalExecutor only, no external integrations.

      Support Status: ${meta.support}
      Python Versions: ${meta.pythonVersions}

      To change version: Edit version and pythonVersion in .flox/pkgs/airflow.nix
    '';
    homepage = "https://airflow.apache.org";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "airflow";
  };
}
