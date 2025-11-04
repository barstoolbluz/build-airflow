# Apache Airflow - Nix/Flox Build Environment

Build modern Apache Airflow versions (3.1.1, 2.11.0, 2.10.5) using **Nix** and **Flox** - versions not available in nixpkgs.

## Why This Exists

**Problem:** Modern Apache Airflow versions are not available in nixpkgs:
- nixpkgs contains Airflow 2.7.3 (released 2023) with known CVEs
- No Kubernetes provider packages available
- Dependency conflicts when trying to add providers via pip

**Solution:** This repository provides build tooling to install Airflow from PyPI using:
- **[Flox Manifest Builds](https://flox.dev/docs/concepts/manifest-builds/)** - Declarative TOML-based builds
- **Nix Flakes** - Traditional Nix ecosystem integration
- **Nix Expressions** *(planned)* - For `nix-build` users

Official Apache Airflow constraint files ensure reproducibility across all build methods.

---

## Supported Versions

| Version | Released | Support Status | Python | K8s Provider | Use Case |
|---------|----------|----------------|--------|--------------|----------|
| **3.1.1** | Oct 2025 | Active Support | 3.9-3.12 | 10.8.2 | New deployments ⭐ |
| **2.11.0** | May 2025 | Limited (until Apr 2026) | 3.9-3.12 | 10.5.0 | Existing 2.x (no Python 3.8) |
| **2.10.5** | Feb 2025 | Limited (until Apr 2026) | 3.8-3.12 | 8.4.x | Python 3.8 required |

---

## Quick Start

### Option 1: Flox Manifest Builds (Recommended)

```bash
# Clone this repository
git clone https://github.com/barstoolbluz/airflow-nix-builds.git
cd airflow-nix-builds

# Activate the build environment
flox activate

# Build Airflow 3.1.1 with Kubernetes support
flox build airflow-3-1-1

# Use the built package
./result-airflow-3-1-1/bin/airflow version
source result-airflow-3-1-1/bin/activate
airflow db init
```

**Available builds (9 total - 3 versions × 3 variants):**

*Airflow 3.1.1 (Latest):*
- `airflow-3-1-1` - Airflow 3.1.1 + Kubernetes provider
- `airflow-full-3-1-1` - Airflow 3.1.1 + multiple providers (k8s, postgres, redis, http, ssh)
- `airflow-minimal-3-1-1` - Minimal Airflow 3.1.1 (LocalExecutor only)

*Airflow 2.11.0:*
- `airflow-2-11-0` - Airflow 2.11.0 + Kubernetes provider
- `airflow-full-2-11-0` - Airflow 2.11.0 + multiple providers
- `airflow-minimal-2-11-0` - Minimal Airflow 2.11.0

*Airflow 2.10.5:*
- `airflow-2-10-5` - Airflow 2.10.5 + Kubernetes provider
- `airflow-full-2-10-5` - Airflow 2.10.5 + multiple providers
- `airflow-minimal-2-10-5` - Minimal Airflow 2.10.5

### Option 2: Nix Flakes

```bash
# Clone this repository
git clone https://github.com/barstoolbluz/airflow-nix-builds.git
cd airflow-nix-builds

# Build Airflow 3.1.1 with Nix flakes (requires --impure for network access)
nix build --impure .#airflow-3-1-1

# Use the built package
./result/bin/airflow version
source result/bin/activate
airflow db init
```

**Available packages (9 total):**

*Named outputs (explicit versions):*
- `airflow-3-1-1`, `airflow-full-3-1-1` - Airflow 3.1.1
- `airflow-2-11-0`, `airflow-full-2-11-0` - Airflow 2.11.0
- `airflow-2-10-5`, `airflow-full-2-10-5` - Airflow 2.10.5

*Dynamic outputs (respects `AIRFLOW_VERSION` env var):*
- `airflow` - Basic build (default: 3.1.1)
- `airflow-full` - Full build (default: 3.1.1)

**Version selection:**
```bash
# Use default (3.1.1)
nix build --impure .#airflow

# Use environment variable
AIRFLOW_VERSION=2.11.0 nix build --impure .#airflow

# Use named output (recommended)
nix build --impure .#airflow-2-11-0
```

### Option 3: Nix Expression (Planned)

Traditional `nix-build` support is planned for broader Nix community compatibility.

---

## Version Selection

Each Airflow version has its own dedicated build - no configuration editing needed!

### For Flox Builds

Simply build the version you need:

```bash
# Latest stable (3.1.1)
flox build airflow-3-1-1

# Previous versions
flox build airflow-2-11-0
flox build airflow-2-10-5

# Full variants with multiple providers
flox build airflow-full-3-1-1
flox build airflow-full-2-11-0

# Minimal variants
flox build airflow-minimal-3-1-1
```

### For Nix Flakes

Use named outputs for explicit versions:

```bash
# Latest stable (3.1.1) - recommended approach
nix build --impure .#airflow-3-1-1

# Previous versions
nix build --impure .#airflow-2-11-0
nix build --impure .#airflow-2-10-5

# Or use environment variable with dynamic outputs
AIRFLOW_VERSION=2.11.0 nix build --impure .#airflow
```

---

## Documentation

- **[BUILDING.md](BUILDING.md)** - Detailed build instructions, troubleshooting, production deployment
- **[SETUP.md](SETUP.md)** - Prerequisites, version details, first-time setup
- **[CLAUDE.md](CLAUDE.md)** - Maintenance guide for adding new Airflow versions
- **[Flox Manifest Builds](https://flox.dev/docs/concepts/manifest-builds/)** - Official Flox documentation
- **[Apache Airflow Docs](https://airflow.apache.org/docs/)** - Official Airflow documentation

---

## How It Works

All build methods:

1. **Create a Python virtualenv** in the output directory
2. **Download official Airflow constraint files** from GitHub for reproducibility
3. **Install Airflow via pip** with providers and constraints
4. **Verify installation** and test provider imports
5. **Package as Nix store path** (flakes) or symlink (Flox builds)

This approach:
- ✅ Solves CVE issues (builds latest versions)
- ✅ Provides Kubernetes provider support
- ✅ Avoids nixpkgs dependency conflicts
- ✅ Uses official Apache Airflow constraint files
- ✅ Supports multiple versions easily
- ✅ Enables runtime version switching (Flox)

---

## Use Cases

### Development Environments

```bash
flox activate
flox build airflow-3-1-1
source result-airflow-3-1-1/bin/activate
airflow standalone
```

### Production Deployments

Compose with Flox environments for postgres/redis:

```toml
[include]
environments = [
  { remote = "barstoolbluz/postgres-headless" },
  { remote = "barstoolbluz/redis-headless" },
]

[hook]
on-activate = '''
  source /path/to/result-airflow-3-1-1/bin/activate
  export AIRFLOW_HOME="$FLOX_ENV_CACHE/airflow"
'''

[services]
airflow-webserver.command = "airflow webserver"
airflow-scheduler.command = "airflow scheduler"
```

### Container Builds

```dockerfile
FROM nixos/nix
RUN nix build --impure github:barstoolbluz/airflow-nix-builds#airflow-3-1-1
CMD ["/nix/store/.../result/bin/airflow", "webserver"]
```

---

## Contributing

Contributions welcome! Please:
1. Test your changes with all three supported versions
2. Update documentation (BUILDING.md, SETUP.md)
3. Ensure both Flox and Nix builds work

---

## About Apache Airflow

[Apache Airflow](https://airflow.apache.org/docs/apache-airflow/stable/) is a platform to programmatically author, schedule, and monitor workflows.

When workflows are defined as code, they become more maintainable, versionable, testable, and collaborative.

### Links

- **Official Repository**: https://github.com/apache/airflow
- **Official Documentation**: https://airflow.apache.org/docs/
- **PyPI Package**: https://pypi.org/project/apache-airflow/
- **Slack Community**: https://s.apache.org/airflow-slack
- **Kubernetes Provider**: https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/

---

## License

Apache Airflow is licensed under the Apache License 2.0.

This build environment configuration is provided as-is for building Apache Airflow.

---

## Acknowledgments

- **Apache Airflow Community** for creating and maintaining Airflow
- **Flox** for declarative environment and build system
- **Nix Community** for reproducible build infrastructure
