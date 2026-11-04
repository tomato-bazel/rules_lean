# rules_lean

Bazel rules for [Lean 4](https://lean-lang.org/), with native [Lake](https://github.com/leanprover/lean4/tree/master/src/lake)
integration that reuses Mathlib's upstream Reservoir cache instead of forcing
each consumer to self-host a multi-gigabyte olean tarball.

- **rules**: `lean_test`, `lean_axiom_test`, `lean_emit`, `lean_library`, `lean_binary`, `lean_prebuilt_library`, `lean_toolchain` — see [docs/lean.md](docs/lean.md).
- **proof gates** (0.7.0): a `sorry` fails the build (`forbid_sorry`, default `True`), and `lean_axiom_test` fails it when a theorem's transitive axiom dependencies leave an allowlist. See [Gating a proof](#gating-a-proof).
- **lake integration**: `lake_workspace` repository rule + `lake` module extension — see [docs/lake.md](docs/lake.md).
- **RulesLean Lean library** (`lean/lib/`): structured introspection of `.olean` files (`RulesLean.Olean`) and Lake workspaces (`RulesLean.Workspace`). Internal helpers under `RulesLean.Internal.*` are unstable; treat them as opt-in and expect API churn between releases. See [lean/lib/RulesLean.lean](lean/lib/RulesLean.lean) for the entry-point doc.
- **lake_imports_manifest** target (opt-in): set `emit_imports_manifest = True` on your `lake.workspace` and `lake_workspace` builds the RulesLean library + `oleanImports` CLI and runs it over every olean in the workspace. Result lands at `@<your-lake-deps>//:lake_imports_manifest` — a TSV of `<path>\t<imported-module>` edges (~5MB / 42k edges for full mathlib), for import-graph analysis, tree-shaking, dead-code detection. **Off by default since 0.6.0**: compiling the CLI leaves a ~149MB `.lake/build/` behind (measured, darwin/arm64) in every `lake_workspace`, whether or not anything reads the manifest. The target still exists when off — it is just empty.

## Install

Add the registry to your `.bazelrc`:

```
common --registry=https://registry.tbzl.dev/
common --registry=https://bcr.bazel.build/
```

In your `MODULE.bazel`:

```python
bazel_dep(name = "rules_lean", version = "0.7.1")

lake = use_extension("@rules_lean//lean:lake.bzl", "lake")
lake.workspace(
    name = "lake_deps",
    lean_toolchain  = "//:lean-toolchain",
    lakefile        = "//:lakefile.lean",
    lake_manifest   = "//:lake-manifest.json",
)
use_repo(lake, "lake_deps")
register_toolchains("@lake_deps//:lean_toolchain_def")
```

## Quick start

Your repo root needs three Lake-convention files:

**`lean-toolchain`** — pins the Lean version (Lake and Bazel both honor it):

```
leanprover/lean4:v4.29.1
```

**`lakefile.lean`** — a deps-only lakefile listing Lake packages you want:

```lean
import Lake
open Lake DSL

package «my-project» where

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git" @ "v4.29.1"
```

**`lake-manifest.json`** — generate once with `elan`-installed `lake`, then commit:

```sh
lake update     # produces lake-manifest.json with all transitive revs pinned
```

Now any `BUILD.bazel` can typecheck Lean code against the resolved packages:

```python
load("@rules_lean//lean:lean.bzl", "lean_test")

lean_test(
    name  = "smoke",
    srcs  = ["Smoke.lean"],
    entry = "Smoke.lean",
    deps  = [
        "@lake_deps//:mathlib",
        "@lake_deps//:batteries",
    ],
)
```

```lean
-- Smoke.lean
import Mathlib.Data.Finset.Basic
example : (∅ : Finset Nat).card = 0 := Finset.card_empty
```

`bazel test //:smoke` will, on first run: download the Lean toolchain, run
`lake update`, run `lake exe cache get` (Reservoir-cached mathlib oleans),
and typecheck `Smoke.lean`.

## Gating a proof

A green `lean_test` means the code type-checks. It does **not** mean anything
was proved: `sorry` is a warning, `lean` exits 0 on it, and until 0.7.0 that
warning was discarded. Two rules close the gap, and neither needs Mathlib.

```python
load("@rules_lean//lean:lean.bzl", "lean_axiom_test", "lean_test")

# `forbid_sorry` defaults True — an admitted goal anywhere in `srcs` is red.
lean_test(
    name = "proofs_test",
    srcs = glob(["**/*.lean"]),
    entry = "Root.lean",
)

# Every named theorem's TRANSITIVE axiom dependencies must be in the allowlist.
lean_axiom_test(
    name = "axioms_test",
    srcs = glob(["**/*.lean"]),
    theorems = [
        "MyProject.main_theorem",
        "MyProject.confluence",
    ],
    # allowed_axioms defaults to [propext, Classical.choice, Quot.sound].
)
```

`lean_axiom_test` generates a Lean module and checks at elaboration time with
`Lean.collectAxioms` — the same API behind `#print axioms`, so it agrees with a
hand audit by construction. The default allowlist is Lean's three standard
axioms; what it **excludes** is the point:

| Axiom | What its presence means |
| --- | --- |
| `sorryAx` | An admitted goal. The theorem is not proved. |
| `Lean.ofReduceBool` | A `native_decide` — the claim rests on the compiler and runtime, not the kernel. |

Tightening the allowlist is the interesting direction. A theorem that needs
only `[propext, Quot.sound]` today and quietly picks up `Classical.choice`
tomorrow has changed, and `allowed_axioms = ["propext", "Quot.sound"]` is what
reports it.

Auditing a compiled dep instead of sources — name the modules to import:

```python
lean_axiom_test(
    name = "axioms_test",
    deps = [":my_library"],
    imports = ["MyProject"],
    theorems = ["MyProject.main_theorem"],
)
```

See [`examples/axiom_audit`](examples/axiom_audit) for both, with the negative
tests that prove each gate actually fires.

## How it works

`lake_workspace` is a Bazel repository rule that:

1. Reads `lean-toolchain`, downloads the matching Lean tarball
   (sha256-pinned for [known versions](lean/private/known_lean_versions.bzl)).
2. Stages your `lakefile` + `lake-manifest.json` into the external repo.
3. Runs `lake update` to materialize all transitive Lake package checkouts at
   the manifest-pinned revs.
4. If mathlib is in the dep graph, runs `lake exe cache get` to fetch
   prebuilt oleans from the upstream Reservoir cache.
5. Generates a `BUILD.bazel` exposing each resolved Lake package as its own
   `lean_prebuilt_library` (target name = Lake's directory name:
   `:mathlib`, `:batteries`, `:Cli`, `:LeanSearchClient`, …).

### What's hermetic

| Layer                | Pinned by                                                |
| -------------------- | -------------------------------------------------------- |
| Lean toolchain       | `sha256` in [`lean/private/known_lean_versions.bzl`](lean/private/known_lean_versions.bzl) |
| Lake dep git revs    | Your committed `lake-manifest.json` (Lake's lockfile)    |
| Mathlib oleans       | Content-addressed by mathlib commit in Reservoir cache (verified by Lake) |

For Lake packages **not** covered by the Reservoir cache (anything outside
mathlib's transitive deps), pass `allow_source_build = True` to `lake.workspace`
— the rule then runs `lake build <pkg>` to compile oleans from source. Slow
but unavoidable for custom deps.

### What's not (yet) hermetic

- Lean versions that aren't pinned in `known_lean_versions.bzl` download
  unverified (with a warning). Add an entry — one line — for any new
  version you need.
- `lake update` reaches the network. The lake-manifest.json constrains
  *what* gets resolved, but the network has to be there. Bazel's normal
  repository-cache mitigates the cost on rebuilds.

## Compatibility

- **Bazel**: 7.4+, bzlmod required.
- **Lean**: 4.29.1 and 4.32.2 exercised; `lean_axiom_test` and the `sorry`
  gate are verified on both. Other versions: add the platform sha256 to
  [`lean/private/known_lean_versions.bzl`](lean/private/known_lean_versions.bzl)
  (compute with `curl -fsSL <url> | shasum -a 256`).
- **Platforms**: darwin_aarch64, darwin_x86_64, linux_x86_64, linux_aarch64.

## Executable dependencies

A `lean_binary` retains its declared compiled dependency closure in its runtime
import root. This includes transitive libraries and modules sharing a top-level
namespace with the executable. Downstream consumers receive this behavior from
the published rule; they do not need a root-only module override.

## Contributing

Rule reference docs (`docs/lean.md`, `docs/lake.md`) are stardoc-generated
from the `.bzl` docstrings and committed to source. After editing a rule
docstring, regenerate:

```sh
bazel run //docs:update
```

CI gates this via `bazel test //docs/...` (diff_test against the committed
output).

## License

MIT.
