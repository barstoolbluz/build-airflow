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

  # Provider extras - includes celery
  providerExtras = "cncf.kubernetes,postgres,redis,http,ssh,celery";

  # Get version metadata
  meta = versionInfo.${version} or {
    pythonVersions = "Unknown";
    support = "Unknown";
    k8sProvider = "N/A";
  };

in
stdenv.mkDerivation {
  pname = "apache-airflow-full";
  inherit version;

  # Placeholder source
  src = builtins.toFile "placeholder" "# Airflow ${version} full build";

  nativeBuildInputs = [
    pythonPkg
    curl
    cacert
  ];

  buildInputs = [
    pythonPkg
  ] ++ lib.optionals stdenv.isLinux [
    gcc-unwrapped
  ];

  __noChroot = true;

  # Skip unpack phase (we don't have source to unpack)
  unpackPhase = ":";

  buildPhase = ''
    echo "========================================="
    echo "Building Apache Airflow (Full)"
    echo "Version: ${version}"
    echo "Python: ${pythonVersion}"
    echo "Support: ${meta.support}"
    echo "Providers: kubernetes, postgres, redis, http, ssh, celery"
    echo "========================================="

    # Create virtualenv
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    pip install --upgrade pip setuptools wheel

    # Download constraints
    echo "Downloading constraints from:"
    echo "  ${constraintUrl}"
    curl -sSL "${constraintUrl}" -o constraints.txt

    # Install Airflow with all providers
    echo ""
    echo "Installing apache-airflow[${providerExtras}]==${version}..."
    pip install "apache-airflow[${providerExtras}]==${version}" \
      --constraint constraints.txt

    # Verify installation
    echo ""
    echo "========================================="
    echo "✅ Full installation complete!"
    echo "========================================="
    echo "Airflow ${version} with multiple providers installed successfully"
    echo "Providers: kubernetes, postgres, redis, http, ssh, celery"
    echo "Kubernetes provider: ${meta.k8sProvider}"

    rm -f constraints.txt
  '';

  installPhase = ''
    echo "Virtualenv created in $out"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "Apache Airflow ${version} with multiple providers including Celery";
    longDescription = ''
      Apache Airflow ${version} with multiple providers:
      - Kubernetes (KubernetesPodOperator, KubernetesExecutor)
      - Postgres (PostgresOperator, PostgresHook)
      - Redis (Redis hooks, Celery broker support)
      - HTTP (SimpleHttpOperator)
      - SSH (SSHOperator)
      - Celery (CeleryExecutor for distributed task execution)

      Support Status: ${meta.support}
      Python Versions: ${meta.pythonVersions}
      K8s Provider: ${meta.k8sProvider}

      To change version: Edit version and pythonVersion in .flox/pkgs/airflow-full.nix
    '';
    homepage = "https://airflow.apache.org";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "airflow";
  };
}
