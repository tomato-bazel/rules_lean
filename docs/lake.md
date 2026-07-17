<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Lake integration for rules_lean.

`lake_workspace` is a repository rule that materializes any Lake workspace
(lakefile + lake-manifest.json) into a Bazel-managed external repo,
downloads the matching Lean toolchain, resolves Lake packages, and exposes
each resolved package as its own `lean_prebuilt_library` target.

Generated targets in `@<name>//:`:

  - `:lean_toolchain` / `:lean_toolchain_def` — register via
    `register_toolchains(...)`.
  - `:<package>` — one `lean_prebuilt_library` per Lake package found under
    `.lake/packages/<package>/`. Target names preserve Lake's directory
    casing (e.g. `:mathlib`, `:batteries`, `:Cli`, `:LeanSearchClient`).
    Consumers depend on multiple packages by listing all needed names.

Fast path for mathlib-based workspaces: if `.lake/packages/mathlib/` is
present after `lake update`, the rule runs `lake exe cache get` to pull
prebuilt oleans from the Reservoir cache (covering mathlib + its transitive
deps). For non-mathlib packages and workspaces, `lake build` produces
oleans from source.

Use via the module extension:

    lake = use_extension("@rules_lean//lean:lake.bzl", "lake")
    lake.workspace(
        name = "lake_deps",
        lean_toolchain = "//:lean-toolchain",
        lakefile = "//:lakefile.lean",
        lake_manifest = "//:lake-manifest.json",
    )
    use_repo(lake, "lake_deps")
    register_toolchains("@lake_deps//:lean_toolchain_def")

    # In a BUILD.bazel:
    lean_test(
        name = "smoke",
        srcs = ["Smoke.lean"],
        entry = "Smoke.lean",
        deps = ["@lake_deps//:mathlib", "@lake_deps//:batteries"],
    )

Hermeticity:
  - The Lean toolchain is downloaded with a known sha256 (see
    private/known_lean_versions.bzl) when the version is pinned there.
    Unpinned versions download unverified (warning emitted).
  - Lake dep revs are pinned by the user's committed lake-manifest.json.
  - Mathlib oleans (when applicable) are content-addressed by mathlib's
    commit hash in the upstream Reservoir cache; integrity is verified by
    Lake.

Constraints on the lakefile passed in:
  - Should be a *deps-only* lakefile (the rule creates a placeholder
    package source). Build directives (`lean_lib`, `lean_exe`) for the
    user's own code don't belong here — those live in Bazel BUILD files
    via the `lean_test` / `lean_emit` rules.

<a id="lake_workspace"></a>

## lake_workspace

<pre>
load("@rules_lean//lean:lake.bzl", "lake_workspace")

lake_workspace(<a href="#lake_workspace-name">name</a>, <a href="#lake_workspace-allow_source_build">allow_source_build</a>, <a href="#lake_workspace-cache_roots">cache_roots</a>, <a href="#lake_workspace-lake_manifest">lake_manifest</a>, <a href="#lake_workspace-lakefile">lakefile</a>, <a href="#lake_workspace-lean_dist_lake">lean_dist_lake</a>,
               <a href="#lake_workspace-lean_dist_toolchain">lean_dist_toolchain</a>, <a href="#lake_workspace-lean_toolchain">lean_toolchain</a>, <a href="#lake_workspace-olean_cache">olean_cache</a>, <a href="#lake_workspace-olean_cache_packages">olean_cache_packages</a>)
</pre>

Materializes a Lake workspace as a Bazel external repo. Produces `:lean_toolchain_def` + one `lean_prebuilt_library` per resolved Lake package (target name = Lake's directory name).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lake_workspace-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lake_workspace-allow_source_build"></a>allow_source_build |  If True, run `lake build <pkg>` for every package whose oleans aren't covered by `lake exe cache get`. Slow for large packages (mathlib from source is ~30 min); fast and necessary for custom Lake deps that have no upstream cache.   | Boolean | optional |  `False`  |
| <a id="lake_workspace-cache_roots"></a>cache_roots |  Module specs to TREE-SHAKE mathlib's olean download to — the roots your workspace actually imports (e.g. ["Mathlib.Data.List.Infix", "Mathlib.Order.Basic"]). Passed to `lake exe cache get <roots>`, which mathlib's cache CLI resolves via `filterByRootModules` to those roots PLUS their transitive closure — so the set is always sound; you cannot under-fetch a module you import.<br><br>Empty (the default) fetches ALL of mathlib, which is what every consumer did before this attr existed. That is rarely what you want: measured against mathlib @ v4.30.0-rc2 (7933 modules, ~2.0 GB of olean+ilean), a Lean→SQL emitter needing 6 roots pulls 1302 modules / 324 MB — an 84% saving. Adding a CategoryTheory + Lie-algebra lane on top cost only +102 MB, so the win is in NOT fetching the other 6373 modules, not in trimming what you import.<br><br>Specs resolve against the src search path, so `Mathlib.Data.List.Infix` and `Mathlib/Data/List/Infix.lean` both work. Ignored for workspaces without mathlib (their `cache` exe does not exist).   | List of strings | optional |  `[]`  |
| <a id="lake_workspace-lake_manifest"></a>lake_manifest |  The committed lake-manifest.json (pins git revs of every Lake dep).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake_workspace-lakefile"></a>lakefile |  The lakefile (deps-only — no library/exe directives for the user's own code).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake_workspace-lean_dist_lake"></a>lean_dist_lake |  The shared toolchain's `bin/lake` (for fetch-time `lake` runs).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake_workspace-lean_dist_toolchain"></a>lean_dist_toolchain |  The shared `lean_toolchain` rule; the workspace re-declares a `toolchain()` pointing at it and aliases `:lean_toolchain` to it.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake_workspace-lean_toolchain"></a>lean_toolchain |  The `lean-toolchain` file. Drives both Lake's toolchain choice and the Lean binary Bazel downloads.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake_workspace-olean_cache"></a>olean_cache |  Base URL/path for prebuilt-olean tarballs (a private cache — never public by default). The LEAN_OLEAN_CACHE repo_env overrides it. Empty → packages without an upstream cache fall back to source build.   | String | optional |  `""`  |
| <a id="lake_workspace-olean_cache_packages"></a>olean_cache_packages |  Lake packages to fetch from the olean cache instead of source-building (e.g. ["cslib"]). Needs a configured cache base; artifact path is <base>/<pkg>-<rev12>-<leanver>-<platform>.tar.gz (the .lake/build tree).   | List of strings | optional |  `[]`  |


<a id="lean_dist"></a>

## lean_dist

<pre>
load("@rules_lean//lean:lake.bzl", "lean_dist")

lean_dist(<a href="#lean_dist-name">name</a>, <a href="#lean_dist-version">version</a>)
</pre>

Extracts the Lean toolchain once; shared by all lake.workspace repos of the same version (deduplicates the multi-GB toolchain across workspaces).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_dist-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_dist-version"></a>version |  Lean version tag (e.g. 'v4.30.0-rc2'); platform is auto-detected.   | String | required |  |


<a id="lake"></a>

## lake

<pre>
lake = use_extension("@rules_lean//lean:lake.bzl", "lake")
lake.workspace(<a href="#lake.workspace-name">name</a>, <a href="#lake.workspace-allow_source_build">allow_source_build</a>, <a href="#lake.workspace-cache_roots">cache_roots</a>, <a href="#lake.workspace-lake_manifest">lake_manifest</a>, <a href="#lake.workspace-lakefile">lakefile</a>, <a href="#lake.workspace-lean_toolchain">lean_toolchain</a>,
               <a href="#lake.workspace-olean_cache">olean_cache</a>, <a href="#lake.workspace-olean_cache_packages">olean_cache_packages</a>)
</pre>


**TAG CLASSES**

<a id="lake.workspace"></a>

### workspace

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lake.workspace-name"></a>name |  -   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lake.workspace-allow_source_build"></a>allow_source_build |  -   | Boolean | optional |  `False`  |
| <a id="lake.workspace-cache_roots"></a>cache_roots |  Module specs to tree-shake mathlib's olean download to (the roots this workspace imports). Resolved to those roots PLUS their transitive closure, so the fetch cannot miss something you import. Empty → fetch ALL of mathlib (~2.0 GB at v4.30.0-rc2). See the repo rule's attr.   | List of strings | optional |  `[]`  |
| <a id="lake.workspace-lake_manifest"></a>lake_manifest |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake.workspace-lakefile"></a>lakefile |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake.workspace-lean_toolchain"></a>lean_toolchain |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lake.workspace-olean_cache"></a>olean_cache |  Base URL/path for prebuilt-olean tarballs (private; overridden by the LEAN_OLEAN_CACHE repo_env). Empty → source-build packages with no cache.   | String | optional |  `""`  |
| <a id="lake.workspace-olean_cache_packages"></a>olean_cache_packages |  Lake packages to fetch from the olean cache instead of building.   | List of strings | optional |  `[]`  |


