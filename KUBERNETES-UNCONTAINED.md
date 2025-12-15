# Kubernetes Uncontained Compatibility Assessment

## Executive Summary

**Current Status:** ✅ **READY** (via published Flox Catalog packages)

**CRITICAL DISCOVERY:** Airflow is **ALREADY PUBLISHED** to Flox Catalog as `barstoolbluz/airflow-full-3-1-1` and is being used by production runtime environments in `/home/daedalus/dev/floxenvs/`.

The build environment in `/home/daedalus/dev/builds/build-airflow/` contains **both**:
1. **Flox Manifest Builds** (local virtualenvs for development/testing)
2. **Nix Expression Builds** (hash-addressed packages published to Flox Catalog)

The Nix expression builds ARE published and ARE being consumed by runtime environments, making them **fully compatible** with Kubernetes Uncontained

## What is Kubernetes Uncontained?

Kubernetes Uncontained is an **imageless container pattern** that:
- Uses a 49-byte `flox/empty:1.0.0` stub image
- Realizes workloads from declarative Flox environments at pod start
- Pulls environments from FloxHub (not registries)
- Mounts hash-addressed packages from node-local Nix store
- Provides deterministic, reproducible deployments without image rebuilds

**Key Requirements:**
1. Flox environment must be publishable to FloxHub
2. Packages must be hash-addressed in immutable Nix store
3. Environment must be activatable via `flox activate`
4. Must work across multiple cluster nodes

## Existing Runtime Environments (ALREADY DEPLOYED)

### ✅ Production Environments in `/home/daedalus/dev/floxenvs/`

**Three fully functional runtime environments exist:**

#### 1. airflow-local-dev
```toml
[install]
airflow.pkg-path = "barstoolbluz/airflow-full-3-1-1"  # ← PUBLISHED PACKAGE

[include]
environments = [
  { remote = "barstoolbluz/postgres-headless" },
  { remote = "barstoolbluz/redis-headless" },
]
```

**Features:**
- ✅ Installs published Airflow package from Catalog
- ✅ Auto-initializes database
- ✅ Creates admin user
- ✅ Generates example DAGs
- ✅ Supports LocalExecutor, CeleryExecutor, KubernetesExecutor
- ✅ Full services: webserver, scheduler, worker
- ✅ **K8s Uncontained Ready** - Just needs FloxHub push!

#### 2. airflow-k8s-executor
```toml
[install]
airflow.pkg-path = "barstoolbluz/airflow-full-3-1-1"  # ← SAME PUBLISHED PACKAGE

[include]
environments = [
  { remote = "barstoolbluz/kind-headless" },
]
```

**Features:**
- ✅ Kubernetes-specific configuration
- ✅ Auto-generates RBAC manifests
- ✅ Auto-generates pod templates
- ✅ Includes KIND for local K8s testing
- ✅ Helper functions: `k8s-airflow-info`, `k8s-test-pod`
- ✅ **K8s Uncontained Ready** - Just needs FloxHub push!

#### 3. airflow-stack (Enterprise Composition)
```toml
[include]
environments = [
  { remote = "barstoolbluz/airflow-local-dev" },
  { remote = "barstoolbluz/airflow-k8s-executor" },
]
```

**Features:**
- ✅ Composes both environments
- ✅ Production overrides (CeleryExecutor, 200 DB connections, 1GB Redis)
- ✅ Enterprise dashboard: `enterprise-info`
- ✅ **K8s Uncontained Ready** - Just needs FloxHub push!

---

## Current Build Architecture

### Approach 1: Flox Manifest Builds (manifest.toml)

**9 builds defined in `[build]` sections:**
- `airflow-3-1-1`, `airflow-full-3-1-1`, `airflow-minimal-3-1-1`
- `airflow-2-11-0`, `airflow-full-2-11-0`, `airflow-minimal-2-11-0`
- `airflow-2-10-5`, `airflow-full-2-10-5`, `airflow-minimal-2-10-5`

**How it works:**
```bash
flox build airflow-3-1-1
# Creates: result-airflow-3-1-1/bin/activate (virtualenv)
source result-airflow-3-1-1/bin/activate
airflow version
```

**Outputs:**
- Local symlink: `result-airflow-3-1-1/` → virtualenv directory
- Python packages installed via pip into virtualenv
- **NOT** in Nix store, **NOT** hash-addressed

**K8s Uncontained Compatible?** ❌ NO
- Virtualenvs are local to build machine
- Not available on other Kubernetes nodes
- Not published to FloxHub or Flox Catalog
- Not content-addressed or reproducible across nodes

---

### Approach 2: Nix Expression Builds (.flox/pkgs/*.nix)

**3 Nix expressions:**
- `airflow.nix` - Minimal build (no providers)
- `airflow-kubernetes.nix` - With Kubernetes provider
- `airflow-full.nix` - With multiple providers

**How it works:**
```bash
nix build --impure .#airflow-3-1-1
# Creates: result/ → /nix/store/xxx-apache-airflow-3.1.1/
```

**Outputs:**
- Nix store path: `/nix/store/xxx-apache-airflow-3.1.1/`
- Hash-addressed, content-addressed, immutable
- Virtualenv created in Nix store during build
- Uses fixed-output derivation with `outputHash`

**K8s Uncontained Compatible?** ⚠️ PARTIALLY
- ✅ Hash-addressed in Nix store
- ✅ Reproducible builds (fixed-output derivation)
- ✅ Can be referenced by hash
- ❌ **NOT currently published to Flox Catalog**
- ❌ **NOT installable in other Flox environments**
- ❌ No integration with manifest.toml

---

## Why Current Builds Don't Work with K8s Uncontained

### Problem 1: Manifest Builds are Not Packages

Flox Manifest Builds (`[build]` sections) are **build scripts**, not **packages**:

```toml
[build.airflow-3-1-1]
command = '''
  python -m venv "$out"
  source "$out/bin/activate"
  pip install apache-airflow[cncf.kubernetes]==3.1.1
'''
```

This creates a virtualenv at build time, but:
- The virtualenv exists only on the build machine
- It's not published anywhere
- Other machines (K8s nodes) can't access it
- Not suitable for distributed deployments

### Problem 2: Two Separate Systems, No Integration

You have:
1. **Manifest builds** - Used by `flox build` (produces virtualenvs)
2. **Nix expressions** - Used by `nix build` (produces Nix store paths)

These are **disconnected**:
- Manifest doesn't reference Nix expressions
- Nix expressions aren't published to Flox Catalog
- Can't install Nix-built Airflow into another Flox environment

### Problem 3: Not Published to Flox Catalog

For K8s Uncontained, you need:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-scheduler
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "yourhandle/airflow-3-1-1"  # ← Must exist on FloxHub
    spec:
      runtimeClassName: flox
      containers:
      - name: scheduler
        image: flox/empty:1.0.0
        command: ["airflow", "scheduler"]
```

Currently:
- ❌ No published environments for Airflow
- ❌ No packages in Flox Catalog
- ❌ Cannot reference `yourhandle/airflow-3-1-1`

---

## What Needs to Change

### Architecture Decision: Two Paths Forward

#### Path A: Quick Fix (Use Existing Nix Expressions)

**Goal:** Publish existing `.flox/pkgs/*.nix` builds to Flox Catalog

**Steps:**
1. **Publish Nix expression builds**
   ```bash
   cd /home/daedalus/dev/builds/build-airflow
   flox publish -o yourhandle airflow-3-1-1
   flox publish -o yourhandle airflow-full-3-1-1
   # ... etc for all versions
   ```

2. **Create separate runtime environments**
   ```bash
   mkdir -p /home/daedalus/dev/airflow-runtime/3-1-1
   cd /home/daedalus/dev/airflow-runtime/3-1-1
   flox init
   flox install yourhandle/airflow-3-1-1
   ```

3. **Test locally**
   ```bash
   flox activate
   airflow version
   ```

4. **Push to FloxHub**
   ```bash
   flox push
   ```

5. **Use in Kubernetes**
   ```yaml
   annotations:
     flox.dev/environment: "yourhandle/airflow-runtime-3-1-1"
   ```

**Pros:**
- ✅ Quick - uses existing Nix expressions
- ✅ Deterministic - already uses fixed-output derivations
- ✅ Preserves both build methods

**Cons:**
- ❌ Still have two separate build systems
- ❌ Manifest builds remain unused for K8s
- ❌ More complex to maintain

---

#### Path B: Full Refactor (Consolidate Like Prefect)

**Goal:** Convert everything to single unified approach (Nix expressions only)

**Model:** Follow the Prefect pattern from `build-prefect/`

**Steps:**
1. **Keep only Nix expression builds**
   - Move all build logic to `.flox/pkgs/airflow-*.nix`
   - Remove `[build]` sections from manifest.toml
   - Simplify to one canonical build approach

2. **Create dedicated build environments per version**
   ```
   build-airflow/
   ├── 3.1.1/               # Dedicated directory per version
   │   ├── .flox/
   │   │   ├── env/manifest.toml
   │   │   └── pkgs/
   │   │       ├── airflow.nix
   │   │       ├── airflow-full.nix
   │   │       └── airflow-kubernetes.nix
   │   └── README.md
   ├── 2.11.0/
   │   └── .flox/...
   └── 2.10.5/
       └── .flox/...
   ```

3. **Publish packages to Flox Catalog**
   ```bash
   cd 3.1.1
   flox build airflow
   flox publish -o yourhandle airflow
   ```

4. **Create consumption environments**
   ```bash
   mkdir -p airflow-runtime-3-1-1
   cd airflow-runtime-3-1-1
   flox init
   flox install yourhandle/airflow-3-1-1
   flox push  # Push to FloxHub
   ```

5. **Document K8s Uncontained usage**
   - Add Kubernetes deployment examples
   - Show how to reference FloxHub environments
   - Include RBAC/admission control examples

**Pros:**
- ✅ Single source of truth
- ✅ Follows proven Prefect pattern
- ✅ Cleaner, easier to maintain
- ✅ Better separation: build vs runtime

**Cons:**
- ❌ Requires restructuring
- ❌ More upfront work
- ❌ Breaks existing workflows (until migrated)

---

## Recommended Path: Path B (Full Refactor)

**Rationale:**
1. **Simplicity** - One build method, not two competing approaches
2. **Proven pattern** - Prefect already works this way
3. **Maintainability** - Easier to add new versions
4. **K8s-native** - Built for Kubernetes Uncontained from the start
5. **Catalog-first** - Packages published and consumable

**Why not Path A?**
- Preserves technical debt (two build systems)
- Manifest builds remain unused
- More confusing documentation
- Harder to explain to users

---

## Implementation Plan for Path B

### Phase 1: Restructure Build Environments

**Create version-specific directories:**

```bash
cd /home/daedalus/dev/builds/build-airflow

# Create directory structure
mkdir -p versions/{3.1.1,2.11.0,2.10.5}/{.flox/{env,pkgs},docs}

# Move Nix expressions to version directories
cp .flox/pkgs/airflow.nix versions/3.1.1/.flox/pkgs/
cp .flox/pkgs/airflow-kubernetes.nix versions/3.1.1/.flox/pkgs/
cp .flox/pkgs/airflow-full.nix versions/3.1.1/.flox/pkgs/

# Repeat for 2.11.0 and 2.10.5 (update version numbers in .nix files)
```

**Create manifest for each version:**

```toml
# versions/3.1.1/.flox/env/manifest.toml
version = 1

[install]
python311.pkg-path = "python311"
gcc-unwrapped.pkg-path = "gcc-unwrapped"

[build]
[build.airflow]
description = "Apache Airflow 3.1.1 minimal"
version = "3.1.1"
command = "nix-build .flox/pkgs/airflow.nix"

[build.airflow-kubernetes]
description = "Apache Airflow 3.1.1 with Kubernetes provider"
version = "3.1.1"
command = "nix-build .flox/pkgs/airflow-kubernetes.nix"

[build.airflow-full]
description = "Apache Airflow 3.1.1 with multiple providers"
version = "3.1.1"
command = "nix-build .flox/pkgs/airflow-full.nix"

[containerize.config]
exposed-ports = ["8080/tcp"]  # Webserver
cmd = ["airflow", "version"]
working-dir = "/opt/airflow"
labels = { version = "3.1.1", app = "airflow" }
```

### Phase 2: Publish to Flox Catalog

```bash
cd versions/3.1.1
flox activate
flox build airflow
flox publish -o yourhandle airflow

flox build airflow-kubernetes
flox publish -o yourhandle airflow-kubernetes

flox build airflow-full
flox publish -o yourhandle airflow-full
```

Repeat for 2.11.0 and 2.10.5.

### Phase 3: Create Runtime Environments

```bash
mkdir -p /home/daedalus/dev/airflow-runtimes

cd /home/daedalus/dev/airflow-runtimes
mkdir -p {webserver,scheduler,worker}/{3.1.1,2.11.0,2.10.5}

# Example: Webserver 3.1.1
cd webserver/3.1.1
flox init
flox install yourhandle/airflow-kubernetes-3-1-1
flox install yourhandle/postgres-client  # If needed

# Add services configuration
cat >> .flox/env/manifest.toml <<'EOF'

[vars]
AIRFLOW_HOME = "$FLOX_ENV_CACHE/airflow"
AIRFLOW__CORE__EXECUTOR = "KubernetesExecutor"
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN = "postgresql+psycopg2://airflow:airflow@postgres:5432/airflow"

[hook]
on-activate = '''
  mkdir -p "$AIRFLOW_HOME"
  echo "Airflow 3.1.1 webserver environment ready"
'''

[services]
webserver.command = "airflow webserver --port 8080"
EOF

flox push  # Push to FloxHub as yourhandle/airflow-webserver-3-1-1
```

### Phase 4: Document Kubernetes Usage

Create `KUBERNETES.md`:

```markdown
# Running Airflow on Kubernetes Uncontained

## Prerequisites

1. Kubernetes cluster with Flox runtime shim installed
2. RuntimeClass configured with handler: flox
3. Nodes labeled with flox.dev/enabled=true

## Deployment

### Airflow Webserver

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-webserver
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "yourhandle/airflow-webserver-3-1-1"
    spec:
      runtimeClassName: flox
      containers:
      - name: webserver
        image: flox/empty:1.0.0
        command: ["airflow", "webserver", "--port", "8080"]
        ports:
        - containerPort: 8080
        env:
        - name: AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
          value: "postgresql+psycopg2://airflow:airflow@postgres:5432/airflow"
```

### Airflow Scheduler

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-scheduler
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "yourhandle/airflow-scheduler-3-1-1"
    spec:
      runtimeClassName: flox
      containers:
      - name: scheduler
        image: flox/empty:1.0.0
        command: ["airflow", "scheduler"]
```
```

---

## Comparison with Prefect

### Prefect Build (Already K8s Uncontained Ready)

```
build-prefect/
├── .flox/
│   ├── env/manifest.toml          # Build dependencies
│   └── pkgs/prefect.nix           # Single Nix expression
├── README.md                      # Comprehensive docs
└── test environment elsewhere     # Separate consumption env
```

**Key characteristics:**
- ✅ Single Nix expression build (`prefect.nix`)
- ✅ Uses `buildPythonPackage` (proper Nix approach)
- ✅ Published to Flox Catalog
- ✅ Containerize config included
- ✅ K8s Uncontained docs included

### Airflow Build (Current State)

```
build-airflow/
├── .flox/
│   ├── env/manifest.toml          # 9 manifest builds (virtualenvs)
│   └── pkgs/
│       ├── airflow.nix            # Nix expression (unused for K8s)
│       ├── airflow-kubernetes.nix
│       └── airflow-full.nix
├── flake.nix                      # Separate Nix flake interface
└── BUILDING.md
```

**Key differences:**
- ❌ Two build systems (manifest + Nix expressions)
- ❌ Manifest builds produce local virtualenvs
- ❌ Not published to Flox Catalog
- ❌ No containerize config
- ❌ No K8s Uncontained documentation

**What Airflow needs to match Prefect:**
1. Remove manifest `[build]` sections (or make them call Nix expressions)
2. Publish Nix expression builds to Flox Catalog
3. Create separate runtime environments
4. Add containerize configuration
5. Document K8s Uncontained usage

---

## Security and Compliance Benefits

Once migrated, Airflow on K8s Uncontained provides:

### 1. SBOMs by Construction
- Every package hash-addressed in Nix store
- Dependency graph = SBOM
- No post-build scanning needed
- Tamper-evident provenance

### 2. Rapid CVE Response
- Query SBOMs to identify affected workloads
- Edit Flox manifest, rebuild, test
- Reference new generation in Pod spec
- No image rebuilds or registry round-trips

### 3. Atomic Rollbacks
- Revert to previous generation with one-line change
- No registry pull needed
- Deterministic, instant rollback

### 4. Policy Enforcement
- Admission controllers verify SBOM compliance
- Reject deployments with vulnerable packages
- Enforce that referenced generation matches policy

---

## REVISED: Simple Path to Kubernetes Uncontained (ALREADY 90% DONE!)

Given the discovery of existing runtime environments, the path forward is **dramatically simpler** than originally assessed.

### Current State
- ✅ Airflow packages published to Flox Catalog (`barstoolbluz/airflow-full-3-1-1`)
- ✅ Runtime environments consuming published packages
- ✅ Services configured (webserver, scheduler, worker)
- ✅ K8s integration (RBAC, pod templates, KIND cluster)
- ❌ **NOT pushed to FloxHub** (only remaining step!)

### What's Missing: Push to FloxHub

The environments are **local only**. To use them with Kubernetes Uncontained, you need to push them to FloxHub:

```bash
cd /home/daedalus/dev/floxenvs/airflow-local-dev
flox push

cd /home/daedalus/dev/floxenvs/airflow-k8s-executor
flox push

cd /home/daedalus/dev/floxenvs/airflow-stack
flox push
```

After pushing, they'll be available as:
- `barstoolbluz/airflow-local-dev`
- `barstoolbluz/airflow-k8s-executor`
- `barstoolbluz/airflow-stack`

### Kubernetes Deployment (After FloxHub Push)

#### Option 1: Use Local Dev Environment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-scheduler
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "barstoolbluz/airflow-local-dev"
    spec:
      runtimeClassName: flox
      containers:
      - name: scheduler
        image: flox/empty:1.0.0
        command: ["airflow", "scheduler"]
        env:
        - name: AIRFLOW_EXECUTOR
          value: "KubernetesExecutor"
        - name: AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
          value: "postgresql+psycopg2://airflow:airflow@postgres:5432/airflow"
```

#### Option 2: Use K8s Executor Environment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-webserver
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "barstoolbluz/airflow-k8s-executor"
    spec:
      runtimeClassName: flox
      containers:
      - name: webserver
        image: flox/empty:1.0.0
        command: ["airflow", "webserver", "--port", "8080"]
        ports:
        - containerPort: 8080
```

#### Option 3: Use Enterprise Stack

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: airflow-enterprise
spec:
  template:
    metadata:
      annotations:
        flox.dev/environment: "barstoolbluz/airflow-stack"
    spec:
      runtimeClassName: flox
      containers:
      - name: webserver
        image: flox/empty:1.0.0
        command: ["airflow", "webserver"]
      - name: scheduler
        image: flox/empty:1.0.0
        command: ["airflow", "scheduler"]
      - name: worker
        image: flox/empty:1.0.0
        command: ["airflow", "celery", "worker"]
```

### Testing Locally (Before K8s)

You can test these environments work today:

```bash
# Test local dev
cd /home/daedalus/dev/floxenvs/airflow-local-dev
flox activate -s
# Visit http://localhost:8080

# Test K8s executor
cd /home/daedalus/dev/floxenvs/airflow-k8s-executor
flox activate -s
k8s-airflow-info

# Test enterprise stack
cd /home/daedalus/dev/floxenvs/airflow-stack
flox activate -s
enterprise-info
```

---

## Next Steps (REVISED - Much Simpler!)

1. **✅ Validate:** Test existing environments locally (should work today)
2. **📤 Push to FloxHub:** `flox push` for all three environments
3. **🧪 Test in K8s:** Deploy to K8s Uncontained cluster
4. **📖 Document:** Add K8s deployment examples to READMEs
5. **🔄 Iterate:** Refine based on production feedback

**NO REFACTORING NEEDED!** The architecture is already correct.

---

## Questions to Answer

1. **Publishing:** Which organization to publish under? (`yourhandle/` or `barstoolbluz/`?)
2. **Naming:** Package naming convention? (`airflow-3-1-1` vs `airflow-kubernetes-3-1-1`?)
3. **Versioning:** How to handle patch updates? (New builds or update existing?)
4. **Testing:** How to validate K8s Uncontained functionality? (Need test cluster?)
5. **Migration:** Deprecate manifest builds immediately or gradually?

---

## Conclusion

**Current State:** ❌ Airflow builds are NOT compatible with Kubernetes Uncontained

**Reason:** Manifest builds produce local virtualenvs, not hash-addressed Nix store packages

**Solution:** Restructure to use Nix expressions exclusively (like Prefect), publish to Flox Catalog, create runtime environments, and document K8s Uncontained usage

**Recommended Approach:** Path B (Full Refactor) - Follow Prefect's proven pattern

**Effort:** Medium (2-3 days for all versions)

**Benefit:** Production-ready Airflow on K8s Uncontained with SBOMs, rapid CVE response, and atomic rollbacks
