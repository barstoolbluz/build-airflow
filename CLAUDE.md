# CLAUDE.md - Airflow Nix Builds Maintenance Guide

This document provides comprehensive guidance for maintaining the Apache Airflow build environments in this repository.

## Repository Overview

This repository provides **multi-version Apache Airflow builds** via two mechanisms:
1. **Nix Flake** (`flake.nix`) - For pure Nix users
2. **Flox Manifest** (`.flox/env/manifest.toml`) - For Flox users

Both systems support the same Airflow versions and build variants, but are maintained independently.

## Supported Versions

Currently supported Airflow versions (as of 2025-11):
- **3.1.1** - Latest (Active Support) ⭐ RECOMMENDED
- **2.11.0** - Latest 2.x (Limited Support until April 2026, Python 3.9+)
- **2.10.5** - Python 3.8 support (Limited Support until April 2026)

## Build Variants

Each Airflow version has three build variants:
1. **Basic** (`airflow-X-Y-Z`) - Kubernetes provider only
2. **Full** (`airflow-full-X-Y-Z`) - Multiple providers (kubernetes, postgres, redis, http, ssh)
3. **Minimal** (`airflow-minimal-X-Y-Z`) - No extra providers, LocalExecutor only

## Adding a New Airflow Version

When Apache releases a new Airflow version, you need to update BOTH systems.

### Step 1: Gather Version Metadata

Research the new version and collect:
- **Version number** (e.g., `3.2.0`)
- **Python versions supported** (e.g., `3.9-3.12`)
- **Kubernetes provider version** (check constraint file)
- **Release date**
- **Support status** (Active Support or Limited Support)
- **Special notes** (e.g., "Python 3.8 dropped", "Breaking changes")

### Step 2: Update Nix Flake (`flake.nix`)

#### 2.1 Add Version Metadata

Locate the `versions` attribute set (around line 18) and add the new version:

```nix
versions = {
  "3.2.0" = {
    python = "3.12";                              # Default Python version
    k8sProvider = "10.9.0";                       # From constraints file
    releaseDate = "2025-12-15";                   # Format: YYYY-MM-DD
    support = "Active Support";                   # Or "Limited Support until <date>"
    pythonVersions = "3.9, 3.10, 3.11, 3.12";   # Comma-separated
    recommended = true;                           # true for latest stable
  };
  # ... existing versions
};
```

**Important**: Set `recommended = false` for older versions when adding a newer one.

#### 2.2 Update Default Version

Change the `defaultVersion` variable (around line 56):

```nix
defaultVersion = "3.2.0";  # Change from old default
```

#### 2.3 Add Named Outputs

Add package outputs for the new version (around line 213):

```nix
packages = {
  # ... existing packages

  # Airflow 3.2.0
  airflow-3-2-0 = mkAirflow "3.2.0" "basic";
  airflow-full-3-2-0 = mkAirflow "3.2.0" "full";
};
```

**Naming Convention**: Replace dots with dashes (e.g., `3.2.0` → `airflow-3-2-0`)

#### 2.4 Update Dev Shell Help Text

Update the `shellHook` (around line 232):

```nix
echo "Supported Versions:"
echo "  3.2.0  - Latest (Active Support) ⭐"
echo "  3.1.1  - Previous stable (Active Support)"
echo "  2.11.0 - Latest 2.x (Limited Support, Python 3.9+)"
```

#### 2.5 Update Build Examples

Update example commands in `shellHook` (around line 250):

```nix
echo "  3. Named outputs:"
echo "     nix build --impure .#airflow-3-2-0"
echo "     nix build --impure .#airflow-3-1-1"
```

### Step 3: Update Flox Manifest (`.flox/env/manifest.toml`)

#### 3.1 Update Hook Message

Update the on-activate message (around line 27):

```toml
echo "Airflow 3.2.0 (Active Support) ⭐"
echo "  flox build airflow-3-2-0         - Kubernetes provider"
echo "  flox build airflow-full-3-2-0    - Multiple providers"
echo "  flox build airflow-minimal-3-2-0 - Minimal (no providers)"
echo ""
echo "Airflow 3.1.1 (Active Support)"
echo "  flox build airflow-3-1-1         - Kubernetes provider"
# ... etc
```

#### 3.2 Add Build Recipes

Add three build recipes for the new version. Place them at the top of the `[build]` section (after the `# AIRFLOW X.Y.Z BUILDS` comment).

**Template for all three builds:**

```toml
# ============================================================================
# AIRFLOW 3.2.0 BUILDS (Active Support, Python 3.9-3.12, K8s Provider 10.9.0)
# ============================================================================

[build.airflow-3-2-0]
version = "3.2.0"
description = "Apache Airflow 3.2.0 with Kubernetes provider (Active Support, Python 3.9-3.12)"
command = '''
AIRFLOW_VERSION="3.2.0"
PYTHON_VERSION="3.12"

echo "Building Apache Airflow ${AIRFLOW_VERSION} with Kubernetes support..."

python -m venv "$out"
source "$out/bin/activate"
pip install --upgrade pip setuptools wheel

CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
echo "Downloading constraints from ${CONSTRAINT_URL}..."
curl -sSL "${CONSTRAINT_URL}" -o /tmp/airflow-constraints.txt

echo "Installing apache-airflow[cncf.kubernetes]==${AIRFLOW_VERSION}..."
pip install "apache-airflow[cncf.kubernetes]==${AIRFLOW_VERSION}" \
  --constraint /tmp/airflow-constraints.txt

echo ""
echo "✅ Installation complete!"
airflow version
echo ""
echo "Kubernetes provider:"
python -c "from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator; print('  KubernetesPodOperator: OK')"

rm -f /tmp/airflow-constraints.txt
'''

[build.airflow-full-3-2-0]
version = "3.2.0"
description = "Apache Airflow 3.2.0 with multiple providers (Active Support, Python 3.9-3.12)"
command = '''
AIRFLOW_VERSION="3.2.0"
PYTHON_VERSION="3.12"

echo "Building Apache Airflow ${AIRFLOW_VERSION} with multiple providers..."

python -m venv "$out"
source "$out/bin/activate"
pip install --upgrade pip setuptools wheel

CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
echo "Downloading constraints from ${CONSTRAINT_URL}..."
curl -sSL "${CONSTRAINT_URL}" -o /tmp/airflow-constraints.txt

echo "Installing apache-airflow with multiple providers..."
pip install "apache-airflow[cncf.kubernetes,postgres,redis,http,ssh]==${AIRFLOW_VERSION}" \
  --constraint /tmp/airflow-constraints.txt

echo ""
echo "✅ Full installation complete!"
airflow version
echo ""
echo "Installed providers:"
airflow providers list 2>/dev/null | grep -E "apache-airflow-providers-(cncf-kubernetes|postgres|redis|http|ssh)" || echo "  (run 'airflow providers list' after activation)"

rm -f /tmp/airflow-constraints.txt
'''

[build.airflow-minimal-3-2-0]
version = "3.2.0"
description = "Minimal Apache Airflow 3.2.0 (LocalExecutor only, Active Support, Python 3.9-3.12)"
command = '''
AIRFLOW_VERSION="3.2.0"
PYTHON_VERSION="3.12"

echo "Building minimal Apache Airflow ${AIRFLOW_VERSION}..."

python -m venv "$out"
source "$out/bin/activate"
pip install --upgrade pip setuptools wheel

CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
echo "Downloading constraints from ${CONSTRAINT_URL}..."
curl -sSL "${CONSTRAINT_URL}" -o /tmp/airflow-constraints.txt

echo "Installing apache-airflow (no extra providers)..."
pip install "apache-airflow==${AIRFLOW_VERSION}" \
  --constraint /tmp/airflow-constraints.txt

echo ""
echo "✅ Minimal installation complete!"
airflow version

rm -f /tmp/airflow-constraints.txt
'''
```

**Key Points for Build Recipes:**
- `version = "X.Y.Z"` - Hardcoded, enables version display in Flox catalog
- `AIRFLOW_VERSION="X.Y.Z"` - Hardcoded in command block
- `PYTHON_VERSION="3.X"` - Choose the latest supported Python version
- **Airflow 3.x**: Include `airflow version` verification (works fine)
- **Airflow 2.x**: Skip `airflow version` verification (requires config setup)

#### 3.3 Update Profile Helpers

Update the default build in profile helpers (around line 335):

```toml
bash = '''
activate-airflow() {
    local build_name="${1:-airflow-3-2-0}"  # Update default
    # ... rest unchanged
}
'''
```

Do the same for `zsh` and `fish` sections.

### Step 4: Test the New Version

#### 4.1 Test Nix Flake Builds

```bash
# Test default build
nix build --impure .#airflow
./result/bin/airflow version

# Test named outputs
nix build --impure .#airflow-3-2-0
nix build --impure .#airflow-full-3-2-0

# Test environment variable override
AIRFLOW_VERSION=3.2.0 nix build --impure .#airflow
```

#### 4.2 Test Flox Builds

```bash
# Activate environment
flox activate

# Test all three variants
flox build airflow-3-2-0
flox build airflow-full-3-2-0
flox build airflow-minimal-3-2-0

# Verify versions
./result-airflow-3-2-0/bin/airflow version
```

#### 4.3 Test Kubernetes Provider

```bash
source result-airflow-3-2-0/bin/activate
python -c "from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator; print('OK')"
```

### Step 5: Update Documentation

#### 5.1 Update README.md

If a README exists, update:
- Supported versions list
- Default version in examples
- Any version-specific notes

#### 5.2 Update BUILDING.md

If a BUILDING.md exists, update:
- Version selection examples
- Known issues for the new version
- Migration notes from older versions

### Step 6: Commit and Push

```bash
git add flake.nix .flox/env/manifest.toml
git commit -m "Add Airflow 3.2.0 support

- Add version metadata for Airflow 3.2.0
- Add Nix flake outputs for 3.2.0
- Add Flox build recipes for 3.2.0 (basic, full, minimal)
- Update default version to 3.2.0
- Update documentation and help text"

git push
```

#### 6.1 Push to FloxHub

```bash
cd /path/to/airflow-nix-builds
flox push --force
```

## Deprecating Old Versions

When a version reaches end-of-life:

### Option 1: Keep for Historical Reference
- Change `recommended = false` in Nix flake
- Update support status to "Deprecated" or "EOL"
- Add deprecation warnings in descriptions

### Option 2: Remove Completely
1. Remove from Nix flake `versions` attribute set
2. Remove named outputs from `packages`
3. Remove build recipes from Flox manifest
4. Remove from hook help text
5. Update README/BUILDING.md

## Special Cases

### Airflow 2.x Builds Require libstdc++

**Important**: Airflow 2.x versions (2.10.5, 2.11.0) require `libstdc++.so.6` for the `re2` package.

**Solution**: The manifest includes:
```toml
[install]
gcc-unwrapped.pkg-path = "gcc-unwrapped"
gcc-unwrapped.priority = 6
```

**Do NOT remove this** until all Airflow 2.x versions are deprecated.

**Symptom if missing**: `ImportError: libstdc++.so.6: cannot open shared object file`

### Airflow 2.x Version Verification

Airflow 2.x cannot run `airflow version` during build because it requires configuration setup.

**For Airflow 2.x builds**: Use simplified output instead:
```bash
echo ""
echo "✅ Installation complete!"
echo "Airflow ${AIRFLOW_VERSION} with Kubernetes provider installed"
```

**For Airflow 3.x builds**: Keep the full verification:
```bash
echo ""
echo "✅ Installation complete!"
airflow version
echo ""
echo "Kubernetes provider:"
python -c "from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator; print('  KubernetesPodOperator: OK')"
```

### Python Version Selection

- **Default to latest Python** supported by that Airflow version
- **Airflow 3.x**: Usually supports Python 3.9-3.12
- **Airflow 2.11.x**: Supports Python 3.9-3.12 (NO Python 3.8!)
- **Airflow 2.10.x**: Supports Python 3.8-3.12

**Note**: Users can override Python version when building:
```bash
# Nix (requires modifying flake)
# Flox (requires editing manifest)
```

### Constraint Files

Airflow publishes constraint files for reproducible builds:
```
https://raw.githubusercontent.com/apache/airflow/constraints-{VERSION}/constraints-{PYTHON_VERSION}.txt
```

**Always use constraints** to ensure compatible dependency versions.

**Verify constraint file exists** before releasing:
```bash
curl -I "https://raw.githubusercontent.com/apache/airflow/constraints-3.2.0/constraints-3.12.txt"
```

## Troubleshooting New Versions

### Build Fails with "No constraint file"
- Check if Apache published constraints for that version
- Try alternative Python version (e.g., 3.11 instead of 3.12)

### Build Succeeds but `airflow version` Fails
- For Airflow 3.x: Investigate the error
- For Airflow 2.x: This is expected, skip version verification

### Import Errors for Kubernetes Provider
- Check Kubernetes provider version in constraint file
- Verify compatibility: https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/

### Dependency Conflicts
- Use constraint file (already included in builds)
- Check Airflow release notes for known issues
- Consider using minimal variant to isolate issue

## Version Tracking

Track new Airflow releases:
- **Apache Airflow Releases**: https://github.com/apache/airflow/releases
- **PyPI**: https://pypi.org/project/apache-airflow/#history
- **Mailing List**: dev@airflow.apache.org

## Quick Reference

### File Locations
- **Nix Flake**: `flake.nix`
- **Flox Manifest**: `.flox/env/manifest.toml`
- **This Guide**: `CLAUDE.md`

### Build Naming Convention
- Version dots → dashes: `3.2.0` → `airflow-3-2-0`
- Basic: `airflow-X-Y-Z`
- Full: `airflow-full-X-Y-Z`
- Minimal: `airflow-minimal-X-Y-Z`

### Testing Checklist
- [ ] Nix default build works
- [ ] Nix named outputs work
- [ ] Nix env var override works
- [ ] Flox basic build works
- [ ] Flox full build works
- [ ] Flox minimal build works
- [ ] Kubernetes provider imports
- [ ] Version command works (3.x only)
- [ ] Documentation updated
- [ ] Pushed to FloxHub

## Notes

- **Always test before pushing** - Build failures affect users immediately
- **Keep both systems in sync** - Nix and Flox should support the same versions
- **Document breaking changes** - If a new version has incompatibilities
- **Be conservative with defaults** - Use well-tested Python versions
- **Prioritize latest stable** - Mark newest stable as `recommended = true`
