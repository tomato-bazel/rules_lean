# Changelog

All notable changes to rules_lean. The format is loosely
[Keep a Changelog](https://keepachangelog.com/) — version headers
mirror the published bazel-registry entries.

## Unreleased

`lake_workspace` gives each workspace its own Mathlib cache directory
(`MATHLIB_CACHE_DIR`) instead of the shared `~/.cache/mathlib`. Two Mathlib
workspaces fetched concurrently on a cold machine both ran `lake exe cache get`
against that one directory, and failed with `curl.cfg` missing or with
`leantar` decompression errors as each deleted or overwrote the other's files.

## 0.7.0 — a `sorry` was a GREEN, SILENT build; and axioms are now a gate

Two failures in the same place, found by trying to put citizen-sh/soma's six
confluence theorems behind a Bazel target. The proofs themselves compiled
first try — `lean_test` over Lean 4 core with no Mathlib worked exactly as
documented, on darwin/arm64 and linux. What did not work is everything that
makes a green check mean something.

**A `sorry` passed.** `lean` reports an admitted goal as a WARNING and exits 0.
`topo_compile` echoed the compiler's output only when the exit code was
non-zero — so the warning was discarded along with the exit code that said
nothing was wrong, and the target went green. Measured, not inferred: a
`theorem … := by sorry` appended to a real proof tree, rebuilt, `PASSED`,
zero output. The control (a genuine type error in the same file) went red, so
the harness worked; it just could not see this.

Two things change. The driver now forwards compiler diagnostics on SUCCESS as
well as failure — which also un-hides `#print axioms`, whose output was going
into the same void, so an `Audit.lean` full of them looked like it had run and
found nothing. And **`forbid_sorry` (default `True`)** makes an admitted goal
a build failure, on every rule that compiles Lean.

> **Behavior change.** A tree containing a `sorry` that built green before now
> fails. That is the point — but it is a real break, so: `forbid_sorry = False`
> on the target restores the old behavior, and does not re-hide the warning.

The gate matches the compiler's message text, which is exactly as brittle as
it sounds, so `//examples/axiom_audit:sorry_is_rejected` is a NEGATIVE test in
CI. If upstream rewords the warning, that test goes green and the job fails on
it rather than the check quietly becoming a no-op. (Byte-identical in 4.29.1
and 4.32.2, both checked in-tree.)

**`#print axioms` prints; it does not gate.** A proof that silently acquires
an axiom — a `sorry` in a lemma three imports down, a `native_decide` that
swaps the kernel for the compiler — keeps printing a line nobody reads. The
new `lean_axiom_test` fails the build instead:

```python
lean_axiom_test(
    name = "axioms_test",
    srcs = glob(["**/*.lean"]),
    theorems = ["Soma.network_confluence", "Soma.run_perm_invariant"],
    # allowed_axioms defaults to [propext, Classical.choice, Quot.sound]
)
```

It generates a Lean module and checks at ELABORATION time with
`Lean.collectAxioms` — the same API behind `#print axioms`, so it agrees with
the hand audit by construction rather than by re-implementing it, and it is
transitive. `RulesLean.Internal.AxiomDeps.declaredAxioms` is NOT that: it is a
header-only scan of axioms a module declares directly, and its own docstring
says the transitive version "lands once there's a concrete consumer pushing on
the shape". soma was the consumer.

The default allowlist is Lean's three standard axioms. What it excludes is the
point: `sorryAx` and `Lean.ofReduceBool`. Tightening it is the interesting
direction — a theorem that needs only `[propext, Quot.sound]` today and picks
up `Classical.choice` tomorrow is a real change, and this reports it.
Successful audits are silent; failed audits name the theorem, its axiom
dependencies, the allowlist, and the disallowed axioms.

Verified by mutation on soma's actual proofs, not by assumption. soma's
`Audit.lean` names eight theorems; with the three-axiom allowlist all eight
pass. Drop `Classical.choice` and **five fail by name** while
`runBarriered_perm_invariant`, `network_confluence_barriered` and
`drive_reaches` still pass, because those genuinely need only two — which is
exactly what soma's README claims for them. A gate that cannot tell those
apart is not a gate.

`//examples/axiom_audit` carries four positive targets and three negative ones
(`*_is_rejected`, `manual`-tagged, run by CI with the exit code asserted
non-zero), plus a control — the same `sorry` file with `forbid_sorry = False`,
which must PASS, so a red negative is attributable to the gate and not to a
broken fixture.

**Lean v4.32.2 is pinned**, all four platforms. It was not in
`known_lean_versions.bzl`, so any workspace on a modern toolchain downloaded
the compiler UNVERIFIED behind a `print()` warning — including soma, whose
`lean-toolchain` says `v4.32.2`. Hashes are of the release ASSETS (immutable),
not `/archive/refs/tags/` tarballs.

## 0.6.2 — two deps can share a top-level namespace

Lean resolves a module name in the **first** `LEAN_PATH` root that owns its
top-level directory and does not fall through to later roots. `_dep_manifest_lines`
handled one consequence of that — a dep colliding with the *consumer's* own
namespace gets staged into the compile root — but not the other: **two deps
colliding with each other**.

Two published modules both rooted at `Pg/` therefore could not both be consumed,
unless the consumer happened to have `Pg/` sources of its own. The failure is
silent and misdirected — the compile dies naming a path inside the *wrong*
repository:

    App/Main.lean:4:0: error: object file
      '.../pg_catalog_lib/Pg/Query/Top.olean' of module Pg.Query.Top does not exist

`Pg/Query/Top.olean` is in pg_query's root; Lean looked only in pg_catalog's,
because that root owns `Pg/` and it stopped there.

Now a top-level namespace owned by more than one dep root is staged, exactly as
one colliding with the consumer already was. Namespaces owned by a single dep and
untouched by the consumer still go on `leanpath` with no copy, so the common case
is unchanged. The decision is per-file, so a dep whose namespaces are partly
contested still contributes its uncontested ones via `leanpath`.

**Why it mattered.** This blocked the whole point of publishing compiled oleans
for any consumer whose sources are rooted elsewhere. Concretely: leangres ships
`pgcatalog` and `pgquery`, both rooted at `Pg/`, and their real consumer is rooted
at `Aion/` — so it could not adopt the compiled artifacts at all and had to keep
recompiling from source.

`//examples/shared_namespace` is the regression test, and it is in CI. Verified by
deliberate break: reverted to the old `_dep_manifest_lines` and confirmed the test
fails with the error above, then restored.

## 0.6.1 — `lean_olean_archive` builds on linux, and is byte-reproducible

`lean_olean_archive` tarred the import root directly with `tar -czhf`. The
import root is a symlink farm into bazel-out, so `-h` reads THROUGH the links
while bazel may still be materialising them, and GNU tar treats that as fatal:

    tar: ./Aion/Db/EntityType/EntityTypeFieldPredicates.olean:
         file changed as we read it

**GNU tar exits 1 on that warning; BSD tar does not.** The rule therefore worked
on macOS and failed on every linux/RBE build — invisible to local verification,
and it took an RBE worker log to see it (observed on aion/sql, green on the same
commit on darwin). Downstream this was not a cosmetic failure: the olean publish
job was *removed* from aion's CI because of it, which is what has been blocking
the cross-repo compiled-olean seam this rule exists to provide.

The rule now stages the import root into a private scratch dir with `cp -RL`,
then tars that without `-h`. `tar` reads a tree nothing else is writing, and `cp`
does not fail on concurrent mtime churn the way `tar` does, so the race is
removed rather than narrowed.

While here: the tarball ships as a release asset that consumers pin by sha256,
so it is now **reproducible**. Three things had to be pinned, not one — entry
order (an `LC_ALL=C`-sorted list via `-T -`, not readdir order), per-entry
mtimes (`touch` to a fixed date, because `cp` stamps the staged copies with the
current time), and the gzip header timestamp (`gzip -n`). `gzip -n` on its own
is not enough and the archive stayed non-reproducible with only it; that was
caught by building the same tree twice a second apart and diffing.

uid/gid/uname/gname are still taken from the builder, so this is reproducible
for a given builder — a CI runner rebuilding the same commit gets identical
bytes — not across accounts.

**And CI now actually runs the rule.** `//examples/olean_roundtrip` has covered
`lean_olean_archive` since 0.4.0, but nothing ever executed it: the fast gate is
`//docs/...` only, and the two Lean jobs go through elan/lake rather than the
Bazel rule. The rule was broken on linux for a week behind six green checks, none
of which touched it. There is now an `olean_archive` PR gate on ubuntu —
ubuntu-only on purpose, since the failure mode is GNU tar exiting 1 where BSD tar
warns, so macOS cannot fail and re-proving it there buys nothing.

The round-trip assertion was also weaker than it looked: it grepped the tar
listing for the olean's path. Drop the `-L` from `cp -RL` and the archive still
contains an entry at that path — a dangling symlink into bazel-out, useless to
consumers — and the grep passed. It now asserts the entry is a regular file with
non-zero bytes, verified by building both the correct and the non-dereferenced
archive and confirming the old check accepted the broken one.

No API change; `out` and the produced tarball layout are unchanged.

## 0.6.0 — the imports manifest is opt-in; `lake_workspace` stops building a CLI it never runs

Every `lake_workspace` materialization compiled the RulesLean `oleanImports` CLI
with the consumer's Lean toolchain, unconditionally. Two things were wrong with
that, and both are now fixed.

**The dep-free path built the CLI and provably never invoked it.** When the
lakefile declares no `require`s, `_lake_workspace_impl` short-circuits — and the
manifest generator it calls with an empty package list writes `""` and returns
before it would reach the binary. So the compile was pure cost. Observed on one
darwin output base, three times over: `ruleslean_lib/` at 149 MB next to a
`lake_imports_manifest.tsv` of **0 bytes**, in the `rules_lang`, `rules_postgres`
and `rules_spec` lake workspaces.

**And even on the dep-ful path, nothing reads the manifest.** It is an
introspection aid — "what does olean X import?" — not an input to compiling Lean.
So it is now behind `emit_imports_manifest`, default `False`:

```python
lake.workspace(
    name = "lake_deps",
    emit_imports_manifest = True,   # only if you actually consume the TSV
    ...
)
```

`@<ws>//:lake_imports_manifest` and the `.tsv` are still declared either way —
empty when off — so no consumer BUILD file has to branch on the attr. Turning it
back on restores the previous contents exactly.

**`_build_ruleslean_library`'s timeout goes 600s → 3600s, and its docstring stops
understating the cost.** It claimed "~3-5s cold". Measured here on darwin/arm64,
Lean v4.30.0-rc2, fresh output base, uncontended: **~9s wall** — but a **149 MB**
`.lake/build/`, per `lake_workspace`. The clock was roughly right; the footprint
is the cost, and it is duplicated across every workspace in an output base. A
separate investigation measured 130.9s / 237.6s / 497.5s for the same step on
darwin, which was **not reproduced here** — so the wall time is
environment-dependent somewhere between ~9s and several minutes, and nobody has
measured it on linux. At ~9s the 600s cap is nowhere near binding; the raise is
insurance for the slow end (a repository-rule timeout is a hard analysis failure,
not a slow build), on a step that now rarely runs at all.

Measured end to end, on a throwaway consumer that `bazel_dep`s on a module with a
dep-free lake workspace and builds one `cc_library` (darwin/arm64):

  before   2.6 GB of `external/`  — 2.5 GB Lean toolchain + 149 MB `ruleslean_lib/`
  after    2.3 MB of `external/`  — no Lean repos materialized at all

with, in the before case, a `lake_imports_manifest.tsv` of **0 bytes** sitting
next to the 149 MB it cost to produce.

## 0.5.5 — resolve deps from the pinned manifest, never `lake update`

Backfilled entry; 0.5.5 shipped to the registry without one.

`_lake_workspace_impl` materialized deps with `lake update`, which regenerates the
lake-manifest.json that was just pinned *and* fires every dep's `post_update`
hook. mathlib's hook runs a hardcoded, unfiltered `lake exe cache get`, pulling
all ~7900 oleans before 0.5.4's tree-shaken `cache_roots` fetch got a say — which
left `cache_roots` shipped-but-inert in 0.5.4. Now a non-mutating `lake env true`
resolves from the committed manifest, no hook fires, and `cache_roots` actually
takes effect. Verify by BYTES on disk, not by the "Already decompressed N" log,
which reports the tree-shaken count either way.

## 0.5.4 — tree-shake mathlib's olean download (`cache_roots`)

`lake.workspace(cache_roots = [...])` restricts mathlib's `lake exe cache get`
to the given root modules plus their transitive closure, instead of fetching all
of mathlib. mathlib's cache CLI already supports this (`get [ARGS]` →
`filterByRootModules`); rules_lean simply never passed the args. The fetch stays
sound — you cannot under-fetch a module you import.

Measured against mathlib @ v4.30.0-rc2 with a Lean→SQL emitter's 6 roots
(`Data.Fintype.Basic`, `Data.Fin.Basic`, `Data.List.Basic`, `Data.List.Infix`,
`Order.Basic`, `Order.BoundedOrder.Basic`):

  full fetch        8297 files  (~2 GB)
  6-root closure     595 files  (52 MB)   — 93% fewer files

Empty `cache_roots` (the default) keeps the fetch-everything behaviour, so
existing workspaces are unaffected.

## 0.5.3 — configurable prebuilt-olean cache

- `lake.workspace` can now fetch a package's prebuilt oleans from a **consumer-configurable
  cache** instead of source-building it (e.g. cslib, which Reservoir doesn't serve — a
  ~2.6k-job compile on every cold output base). Declare `olean_cache_packages = ["cslib"]`;
  the cache base is set via the `olean_cache` tag attr (MODULE) or the `LEAN_OLEAN_CACHE`
  repo_env (`--repo_env=...` in .bazelrc — the repo_env wins). Never hardcoded/public.
  Artifact path: `<base>/<pkg>-<rev12>-<leanver>-<platform>.tar.gz` (the package's
  `.lake/build` tree). No base configured → source-build fallback (allow_source_build).
- Each resolved package now also exposes a `:<pkg>_build_tree` filegroup, so producing the
  cache tarball is a hermetic `pkg_tar` over it (no manual host `tar` / AppleDouble cruft).
- Validated: with the cache set, cslib is fetched + unpacked (0 source-build jobs), green.

## 0.5.2 — shared Lean toolchain (dedup)

- The `lake` module extension now extracts the Lean toolchain **once per version**
  into a shared `lean_dist` repo; every `lake.workspace` symlinks it instead of
  extracting its own ~2.5G copy. Previously N workspaces (e.g. a project plus the
  lake workspaces of `rules_lang` / `rules_postgres` / `rules_spec`) each carried a
  full toolchain — 4× the same toolchain ≈ 10G **per output base**, the dominant
  cause of multi-GB Lean checkouts / CI ENOSPC. Now 1× per version.
- Backward-compatible: `@<ws>//:lean_toolchain_def` is still a real `toolchain()`
  (so `register_toolchains(...)` is unchanged) — it now points at the shared
  `lean_dist` toolchain; `@<ws>//:lean_toolchain` is an alias to it. The per-package
  `lean_prebuilt_library` targets and the imports manifest are unchanged.

## 0.4.0 — compiled libraries + cross-repo olean artifacts

- New `lean_library`: compiles `.lean` sources to a persistent `.olean`
  import-root tree (build outputs) and exposes it as `LeanInfo`, so one module
  can be a **compiled** dependency of another (no source re-share, no
  recompile). `DefaultInfo` carries the library's own tree; `LeanInfo` carries
  the transitive closure (own + deps).
- New `lean_olean_archive`: bundles a `lean_library`'s own `.olean` tree into a
  tarball — the deployable cross-repo release artifact.
- New `lean_imported_library`: exposes an unpacked `.olean` tarball (e.g. from
  an `http_archive` of a release asset) as `LeanInfo` with no recompile — the
  consume side. Shares the `lean_prebuilt_library` implementation.
- These three form the cross-repo compiled-olean seam (split a monolithic Lean
  library into modules that publish/consume prebuilt oleans). `.olean` is
  neither Lean-version- nor architecture-portable, so artifacts are built
  per-`(lean-version, os, arch)` and consumers pin the matching toolchain;
  Lean rejects a mismatched olean loudly at use.
- Round-trip example under `examples/olean_roundtrip/`.
- **Cross-namespace deps.** A `lean_library` dep that shares the consumer's
  top-level namespace (e.g. two libs both under `Aion/`) is staged into the
  single compile root, since Lean commits to the first `LEAN_PATH` root owning a
  namespace and won't fall through to siblings. Disjoint deps (Mathlib, …) stay
  on `LEAN_PATH`, uncopied. This makes `lean_library`→`lean_library` deps within
  one namespace work (the basis for splitting a monolith in place).
- **Shell-free compile.** All four rules (`lean_library`, `lean_test`,
  `lean_emit`, `lean_main_test`) now drive the compiler through a self-contained
  Lean topo-compile driver (`lean/private/topo_compile.lean`, invoked
  `lean --run …` via `ctx.actions.run`) instead of a `run_shell` `tsort`
  pipeline — staging/copying uses native `IO.FS`; the only subprocess is `lean`.
  `lean_test`/`lean_main_test` now type-check / run at build time (a failure
  fails the build); their test executable is a trivial pass.

## 0.3.9 — import-topological compile order (`glob()`-safe srcs)

- `lean_test`, `lean_emit`, and `lean_main_test` now compile their
  `srcs` in **import-topological order** instead of literal list
  order. Previously, Lean's requirement that a module's imports be
  compiled to `.olean` first meant `srcs` had to be hand-ordered
  with dependencies before dependents — and a natural
  `glob(["**/*.lean"])` would fail, because a root file like
  `Trading.lean` sorts before `Trading/Fx/Basic.lean` (`.` < `/`)
  yet imports it. Now the generated runner derives the order at
  execution time: it parses each staged file's `import` lines,
  keeps edges to modules that are themselves in `srcs`, and
  `tsort`s the graph. **`srcs = glob([...])` now Just Works**;
  explicit ordered lists keep working unchanged (any valid manual
  order is already a valid topological order).
- Implementation: a portable bash helper (`__lean_topo_compile`,
  shared via `_topo_compile_block`) using only
  `grep`/`sed`/`cut`/`tsort`/`mktemp` — no bash-4 associative
  arrays, so it runs on macOS's stock bash 3.2. Out-of-`srcs`
  imports (Mathlib, dep packages) are ignored; genuine import
  cycles still fail the build (Lean rejects them downstream).

## 0.3.5 — `lean_main_test` rule

- New `lean_main_test(name, srcs, entry, deps, data)` rule in
  `lean/lean.bzl`. Compiles + runs a Lean entry whose
  `main : IO UInt32` returns the test result via its exit code
  (0 = pass, non-zero = fail). No expected-output diff required —
  use when the Lean script self-validates (round-trip stability,
  structural equivalence) and you'd otherwise need a committed
  `expected.txt` fixture just to flag drift. Accepts the same
  `deps` (LeanInfo) + `data` (workspace-relative staging) attrs
  as `lean_emit` / `lean_regen_test`.
- New smoke `examples/regen_smoke/regen_smoke_exit` runs
  `ExitZero.lean` (`pure 0`) to exercise the happy path. A
  companion `ExitOne.lean` (`pure 1`) is committed for manual
  negative testing.

## 0.3.4 — `lean_emit.data` accepts external-repo files

- `lean_emit.data` now stages files at their workspace-relative path
  (e.g. `examples/regen_smoke/fixture.txt`) instead of the package-
  relative path the 0.3.3 release used. Externally-sourced data
  (`@some_repo//path:file`) is staged at `path/file` — the `..//<canon>`
  prefix in bazel's external-repo short_path is stripped. This lets
  consumers pull fixtures directly from upstream repos
  (e.g. `@postgres_src//:src/include/catalog/pg_namespace.dat`)
  instead of vendoring them.
- Smoke updated: `examples/regen_smoke/EchoFixture.lean` reads the
  full workspace-relative path.

## 0.3.3 — `lean_emit.data` attr

- `lean_emit` (and `lean_regen_test`) gain a `data` attr — non-Lean
  fixture files staged alongside `srcs` in the action's work directory
  without being compiled. The entry runs from that work dir, so it
  can `IO.FS.readFile` them by their package-relative path. Typical
  use: `.dat` / `.txt` / `.json` inputs the entry parses. Enabled
  rules_postgres' Lean-native `Pg.Catalog.Dat` round-trip gate
  against the vendored `pg_namespace.dat` sample.
- New smoke `examples/regen_smoke/regen_smoke_data` exercises the
  attr end-to-end: a Lean main reads `fixture.txt` and echoes it;
  the diff_test verifies the captured stdout matches the same
  `fixture.txt` (proving the data file is reachable from the Lean
  entry's relative-path `readFile`).

## 0.3.2 — `lean_regen_test` macro

- New `lean_regen_test(name, srcs, entry, expected, ...)` macro in
  `lean/lean.bzl`. Wraps `lean_emit` + skylib `diff_test` to assert a
  committed artifact matches the current Lean-emit output for a given
  Lean main. Captures the "Lean spec is source-of-truth; emitted X
  was generated from it" pattern that rules_postgres' Pg.Ir cluster
  Gate 1 was building on top of `lean_emit` + `diff_test` by hand.
- Smoke test under `examples/regen_smoke/` exercises the macro
  end-to-end against a tiny `Hello.lean` and a committed
  `expected.txt`.

## 0.3.1 — External-repo Lean sources

- `_module_path` and `_lean_test_impl` now handle external-repo
  source layouts (`../<repo>+/<package>/<file>` short_paths). Lets
  `lean_library` and `lean_test` targets in a consumer module
  reference Lean sources from a `bazel_dep` repo without copying
  the files into the consumer's tree. Used by rules_postgres'
  `lean/Pg/Ir/Emit/` modules when consumed through the registry
  rather than through a `local_path_override`.

## 0.3.0 — RulesLean Lean library + lake_imports_manifest

- Promote `v0.3.0-rc1` and pin to Lean `v4.30.0-rc2` for cslib compatibility.
- Add `RulesLean.Internal.Closure` (transitive olean closure computed from the
  Lake manifest) and `RulesLean.Internal.AxiomDeps` (`declaredAxioms` +
  `isAxiom`, Internal v0.1).
- CI: add a `ruleslean_library` matrix job so the in-tree Lean library is
  built + tested on every PR.
- Untrack `.vscode/` and notebook scratch artifacts; tighten `.gitignore`.

### 0.3.0-rc1 — RulesLean scaffold + manifest tooling

- Introduce the `RulesLean` Lean library under `lean/lib/` (Olean + Lake) and
  wire it through Bazel.
- Add the `lake_imports_manifest` target: workspace API,
  `exportedConstants` + `containsConstant`, and the `Internal` namespace
  convention with `namespacePackageIndex`.
- Add `tools/reservoir_manifest.py` — a stdlib-only Reservoir index fetcher.
- Update the install snippet to point at `fastverk/bazel-registry`.

## 0.2.2 — Un-dev bazel_skylib

- Promote `bazel_skylib` out of `dev_dependency` so downstream consumers can
  actually `load()` `lean/BUILD.bazel` without re-declaring it.

## 0.2.1 — README, license, CI, smoke test

- Bump module version to 0.2.1.
- Add `README.md`, MIT `LICENSE`, and the PR-gate CI workflow.
- Add a Batteries-only `lake_workspace` smoke test.
- Apply buildifier formatting fixes across the tree.

## 0.2.0 — Generalized Lake integration + stardoc

- Generalize the Lake integration so `lake_workspace` works for arbitrary
  Lake projects instead of being hard-coded to a single layout.
- Add stardoc generation for the public rules.

## 0.1.0 — Initial release

- First public cut of `rules_lean`: `lean_test`, `lean_emit`,
  `lean_prebuilt_library`, `lean_toolchain`, and the initial `lake_workspace`
  repository rule + `lake` module extension reusing Mathlib's Reservoir
  cache.
