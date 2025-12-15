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
  version = "3.1.3";           # Airflow version to build
  pythonVersion = "3.12";      # Python version for constraint file URL

  # Version metadata for reference
  versionInfo = {
    "3.1.3" = {
      pythonVersions = "3.9, 3.10, 3.11, 3.12, 3.13";
      support = "Active Support";
      k8sProvider = "10.9.0";
    };
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

  # Provider extras
  providerExtras = "cncf.kubernetes";

  # Get version metadata
  meta = versionInfo.${version} or {
    pythonVersions = "Unknown";
    support = "Unknown";
    k8sProvider = "N/A";
  };

  # Fixed-output derivation to download pip packages (allowed network access)
  pipCache = stdenv.mkDerivation {
    name = "airflow-kubernetes-${version}-pip-cache";

    nativeBuildInputs = [ pythonPkg curl cacert ];

    # Placeholder source
    src = builtins.toFile "requirements.txt" ''
      apache-airflow[${providerExtras}]==${version}
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
        "apache-airflow[${providerExtras}]==${version}" \
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
        then "sha256-GmpYhoMp/3UTGLsOkSpC3+uuz8ZMo4UCJ4whLyH+XFM="  # macOS Apple Silicon
      else if stdenv.isDarwin
        then "sha256-p/dPioX3+W7UIVVmQ9brFLJ7+ebkQQBJV/UP2vdp5PA="  # macOS Intel
      else if stdenv.isLinux && stdenv.isAarch64
        then "sha256-SCmnE38JKLFE9ob8YbEAUkhpcEm4TJFnuPFyYJ09pek="  # Linux ARM64
      else "sha256-sc2eYDKUUUPOuqdIQ63rrMlXAelCdCMS0edB6uIhrDQ="; # Linux x86_64
  };

in
stdenv.mkDerivation {
  pname = "apache-airflow-kubernetes";
  inherit version;

  # Placeholder source
  src = builtins.toFile "placeholder" "# Airflow ${version} kubernetes build";

  nativeBuildInputs = [
    pythonPkg
  ];

  buildInputs = [
    pythonPkg
  ] ++ lib.optionals stdenv.isLinux [
    gcc-unwrapped
  ];

  # Skip unpack phase (we don't have source to unpack)
  unpackPhase = ":";

  buildPhase = ''
    echo "========================================="
    echo "Building Apache Airflow (Kubernetes)"
    echo "Version: ${version}"
    echo "Python: ${pythonVersion}"
    echo "Support: ${meta.support}"
    echo "K8s Provider: ${meta.k8sProvider}"
    echo "========================================="

    # Create virtualenv
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    # Install from pre-downloaded packages (no network needed)
    echo ""
    echo "Installing apache-airflow[${providerExtras}]==${version} from cache..."
    pip install --no-index --find-links ${pipCache} \
      "apache-airflow[${providerExtras}]==${version}"

    # Verify installation
    echo ""
    echo "========================================="
    echo "✅ Installation complete!"
    echo "========================================="
    echo "Airflow ${version} with Kubernetes provider installed successfully"
    echo "Kubernetes provider: ${meta.k8sProvider}"
  '';

  installPhase = ''
    echo "Virtualenv created in $out"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "Apache Airflow with Kubernetes provider";
    longDescription = ''
      Apache Airflow ${version} with Kubernetes provider.
      Includes KubernetesPodOperator for running tasks in K8s pods.

      Support Status: ${meta.support}
      Python Versions: ${meta.pythonVersions}
      K8s Provider: ${meta.k8sProvider}

      To change version: Edit version and pythonVersion in .flox/pkgs/airflow-kubernetes.nix
    '';
    homepage = "https://airflow.apache.org";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "airflow";
  };
}
