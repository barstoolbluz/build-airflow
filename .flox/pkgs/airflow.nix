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
  version = "2.11.0";          # Airflow version to build
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

  # Fixed-output derivation to download pip packages (allowed network access)
  pipCache = stdenv.mkDerivation {
    name = "airflow-minimal-${version}-pip-cache";

    nativeBuildInputs = [ pythonPkg curl cacert ];

    # Placeholder source
    src = builtins.toFile "requirements.txt" ''
      apache-airflow==${version}
    '';

    unpackPhase = ":";

    buildPhase = ''
      mkdir -p $out

      # Create temporary venv for downloading
      ${pythonPkg}/bin/python -m venv venv
      source venv/bin/activate

      pip install --upgrade pip setuptools wheel

      # Download constraints
      curl -sSL "${constraintUrl}" -o constraints.txt

      # First download build dependencies
      pip download pip setuptools wheel setuptools_scm --dest $out

      # Download all packages without installing, preferring binary wheels
      pip download \
        "apache-airflow==${version}" \
        --constraint constraints.txt \
        --prefer-binary \
        --dest $out
    '';

    installPhase = "true";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Platform-specific hashes (pip downloads different wheels per platform)
    outputHash =
      if stdenv.isDarwin && stdenv.isAarch64
        then "sha256-R/pdXvd1HOiTaQynL+LYKSLAYSp5jNF5qEAReeqT4os="  # macOS Apple Silicon
      else if stdenv.isDarwin
        then "sha256-e7sUTbMMRD8PXfy8ggp6wIuexBmiwxuYfWt6VjXZp3w="  # macOS Intel
      else "sha256-Uk4Lo9rdTkKGtmQxTqTetlxY+S0bSkSa2nN6rJNawuY="; # Linux
  };

in
stdenv.mkDerivation {
  pname = "apache-airflow-minimal";
  inherit version;

  # Placeholder source (we install from PyPI)
  src = builtins.toFile "placeholder" "# Airflow ${version} minimal build";

  nativeBuildInputs = [
    pythonPkg
  ];

  buildInputs = [
    pythonPkg
  ] ++ lib.optionals stdenv.isLinux [
    gcc-unwrapped  # For libstdc++.so.6 (Airflow 2.x re2 package)
  ];

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

    # Install from pre-downloaded packages (no network needed)
    echo ""
    echo "Installing apache-airflow==${version} from cache (no providers)..."
    pip install --no-index --find-links ${pipCache} \
      "apache-airflow==${version}"

    # Verify installation
    echo ""
    echo "========================================="
    echo "✅ Installation complete!"
    echo "========================================="
    echo "Airflow ${version} installed successfully (minimal variant)"
    echo "Variant: Minimal (LocalExecutor only)"
  '';

  installPhase = ''
    echo "Virtualenv created in $out"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "Apache Airflow - Minimal installation (no providers)";
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
