<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Bazel rules for Lean 4.

User-facing rules:
  lean_toolchain         — registers a Lean compiler binary + runtime tree.
                           Normally produced by `lake_workspace` (see lake.bzl);
                           can also be declared by hand against a hermetic
                           lean tarball.
  lean_prebuilt_library  — exposes a tree of prebuilt .olean files as a
                           LeanInfo provider consumable via the `deps` attr.
                           The `path_marker` file's parent directory becomes
                           the LEAN_PATH entry.
  lean_library           — compile a set of .lean sources to a persistent
                           .olean import-root tree (build outputs) and expose
                           it as LeanInfo. Lets one module be a *compiled*
                           dep of another (no source re-sharing). Transitive:
                           its LeanInfo carries its deps' closure too.
  lean_olean_archive     — bundle a lean_library's own .olean tree into a
                           tarball — the deployable cross-repo release artifact.
  lean_imported_library  — expose an unpacked .olean tarball (e.g. from an
                           `http_archive` of a release asset) as LeanInfo,
                           with NO recompile. The cross-repo consume side.
  lean_test              — stages a set of .lean sources into a module-path
                           layout and invokes the compiler on an entry point.
                           Returns 0 if all type-check, nonzero otherwise.
                           Accepts `deps = [LeanInfo]` and prepends each
                           dep's import root to LEAN_PATH.
  lean_emit              — like lean_test, but the entry file defines
                           `main : IO Unit`; runs it and captures stdout to
                           a declared output file. The Lean kernel becomes
                           the source of truth for emitted artifacts (SQL,
                           TTL, Markdown). Same `deps` plumbing as lean_test.

`lean_library`/`lean_olean_archive`/`lean_imported_library` (added 0.4.0) are
the cross-repo compiled-artifact seam: split a monolithic Lean library into
modules, publish each module's `.olean` tree as a per-`(lean-version, os, arch)`
release tarball, and have downstreams consume the prebuilt oleans without
recompiling. `.olean` is neither Lean-version- nor architecture-portable (it is
a compacted heap image), so a consumer must pin the SAME `lean-toolchain` and
`select()` the matching-platform artifact; Lean itself rejects a mismatched
olean loudly at use.

<a id="lean_binary"></a>

## lean_binary

<pre>
load("@rules_lean//lean:lean.bzl", "lean_binary")

lean_binary(<a href="#lean_binary-name">name</a>, <a href="#lean_binary-deps">deps</a>, <a href="#lean_binary-srcs">srcs</a>, <a href="#lean_binary-entry">entry</a>)
</pre>

A runnable Lean executable: compiles srcs to an olean root and `lean --run`s the entry with runtime argv.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_binary-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_binary-srcs"></a>srcs |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_binary-entry"></a>entry |  Module-path of the src whose `main` is the entry point.   | String | required |  |


<a id="lean_emit"></a>

## lean_emit

<pre>
load("@rules_lean//lean:lean.bzl", "lean_emit")

lean_emit(<a href="#lean_emit-name">name</a>, <a href="#lean_emit-deps">deps</a>, <a href="#lean_emit-srcs">srcs</a>, <a href="#lean_emit-data">data</a>, <a href="#lean_emit-out">out</a>, <a href="#lean_emit-entry">entry</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_emit-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_emit-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_emit-srcs"></a>srcs |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_emit-data"></a>data |  Non-Lean files staged alongside `srcs` in the action's work directory (NOT compiled). The Lean entry runs from that directory, so it can `IO.FS.readFile` them by their package-relative path. Typical use: fixture `.dat` / `.txt` / `.json` inputs the entry processes.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_emit-out"></a>out |  The emitted artifact (one file). Filename should reflect the artifact kind.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lean_emit-entry"></a>entry |  Path of the entry-point .lean file (relative to the package) defining `main : IO Unit`. Stdout is captured to `out`.   | String | required |  |


<a id="lean_imported_library"></a>

## lean_imported_library

<pre>
load("@rules_lean//lean:lean.bzl", "lean_imported_library")

lean_imported_library(<a href="#lean_imported_library-name">name</a>, <a href="#lean_imported_library-srcs">srcs</a>, <a href="#lean_imported_library-path_marker">path_marker</a>)
</pre>

Expose an unpacked .olean release tarball as LeanInfo (no recompile).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_imported_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_imported_library-srcs"></a>srcs |  All files of the unpacked .olean tree (typically `@<archive_repo>//:all` or a `glob`).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_imported_library-path_marker"></a>path_marker |  Anchor file inside the unpacked import root (the archive's `.lean_root`). Its parent dir becomes the LEAN_PATH entry.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="lean_library"></a>

## lean_library

<pre>
load("@rules_lean//lean:lean.bzl", "lean_library")

lean_library(<a href="#lean_library-name">name</a>, <a href="#lean_library-deps">deps</a>, <a href="#lean_library-srcs">srcs</a>)
</pre>

Compile .lean sources to a persistent .olean import-root tree and expose it as LeanInfo.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_library-deps"></a>deps |  Compiled Lean libraries this one imports. Same-top-namespace deps are staged into the compile root; disjoint ones are on LEAN_PATH. All propagate transitively in this library's LeanInfo.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_library-srcs"></a>srcs |  All .lean files in this library. Module path is derived from the file's path relative to its own package. Compiled in import-topological order, so list order is irrelevant (a `glob()` is fine).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |


<a id="lean_main_test"></a>

## lean_main_test

<pre>
load("@rules_lean//lean:lean.bzl", "lean_main_test")

lean_main_test(<a href="#lean_main_test-name">name</a>, <a href="#lean_main_test-deps">deps</a>, <a href="#lean_main_test-srcs">srcs</a>, <a href="#lean_main_test-data">data</a>, <a href="#lean_main_test-entry">entry</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_main_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_main_test-deps"></a>deps |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_main_test-srcs"></a>srcs |  All .lean files needed to compile the entry. Compiled in import-topological order, so list order is irrelevant (a `glob()` is fine).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_main_test-data"></a>data |  Non-Lean files staged at their workspace-relative path in the action's work directory. The Lean entry runs from that directory, so it can `IO.FS.readFile` them.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_main_test-entry"></a>entry |  Path of the entry-point .lean file (relative to the package) defining `main : IO UInt32` (test result = exit code).   | String | required |  |


<a id="lean_olean_archive"></a>

## lean_olean_archive

<pre>
load("@rules_lean//lean:lean.bzl", "lean_olean_archive")

lean_olean_archive(<a href="#lean_olean_archive-name">name</a>, <a href="#lean_olean_archive-out">out</a>, <a href="#lean_olean_archive-library">library</a>)
</pre>

Bundle a lean_library's .olean import-root tree into a deployable tarball.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_olean_archive-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_olean_archive-out"></a>out |  Output tarball name (default `<name>.tar.gz`).   | String | optional |  `""`  |
| <a id="lean_olean_archive-library"></a>library |  The `lean_library` whose own .olean tree is archived.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="lean_prebuilt_library"></a>

## lean_prebuilt_library

<pre>
load("@rules_lean//lean:lean.bzl", "lean_prebuilt_library")

lean_prebuilt_library(<a href="#lean_prebuilt_library-name">name</a>, <a href="#lean_prebuilt_library-srcs">srcs</a>, <a href="#lean_prebuilt_library-path_marker">path_marker</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_prebuilt_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_prebuilt_library-srcs"></a>srcs |  All files in the prebuilt-olean tree (typically `glob(["lib/**"])`).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_prebuilt_library-path_marker"></a>path_marker |  Anchor file inside the import-root directory. The marker's parent is the LEAN_PATH entry.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="lean_test"></a>

## lean_test

<pre>
load("@rules_lean//lean:lean.bzl", "lean_test")

lean_test(<a href="#lean_test-name">name</a>, <a href="#lean_test-deps">deps</a>, <a href="#lean_test-srcs">srcs</a>, <a href="#lean_test-entry">entry</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_test-deps"></a>deps |  Prebuilt Lean libraries. Same-top-namespace deps are staged into the compile root; disjoint ones are on LEAN_PATH.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="lean_test-srcs"></a>srcs |  All .lean files in the proof tree. Module path is derived from the file's path relative to this BUILD.bazel's package. Compiled in import-topological order, so list order is irrelevant — `glob(["**/*.lean"])` is fine.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="lean_test-entry"></a>entry |  Path of the entry-point .lean file relative to the package.   | String | required |  |


<a id="lean_toolchain"></a>

## lean_toolchain

<pre>
load("@rules_lean//lean:lean.bzl", "lean_toolchain")

lean_toolchain(<a href="#lean_toolchain-name">name</a>, <a href="#lean_toolchain-lean">lean</a>, <a href="#lean_toolchain-runtime">runtime</a>)
</pre>



**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="lean_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="lean_toolchain-lean"></a>lean |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="lean_toolchain-runtime"></a>runtime |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="LeanInfo"></a>

## LeanInfo

<pre>
load("@rules_lean//lean:lean.bzl", "LeanInfo")

LeanInfo(<a href="#LeanInfo-markers">markers</a>, <a href="#LeanInfo-files">files</a>)
</pre>

A Lean library: a directory of importable .olean files, exposed via a marker file whose parent directory is the LEAN_PATH entry.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="LeanInfo-markers"></a>markers |  depset[File]: each marker's parent directory IS a LEAN_PATH entry.    |
| <a id="LeanInfo-files"></a>files |  depset[File]: all .olean files (and the marker) needed when this lib is consumed.    |


<a id="LeanToolchainInfo"></a>

## LeanToolchainInfo

<pre>
load("@rules_lean//lean:lean.bzl", "LeanToolchainInfo")

LeanToolchainInfo(<a href="#LeanToolchainInfo-lean">lean</a>, <a href="#LeanToolchainInfo-runtime">runtime</a>)
</pre>

Lean 4 compiler binary + runtime tree.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="LeanToolchainInfo-lean"></a>lean |  File: the lean compiler binary (executable).    |
| <a id="LeanToolchainInfo-runtime"></a>runtime |  depset[File]: stdlib oleans, shared libs, etc.    |


<a id="lean_regen_test"></a>

## lean_regen_test

<pre>
load("@rules_lean//lean:lean.bzl", "lean_regen_test")

lean_regen_test(<a href="#lean_regen_test-name">name</a>, <a href="#lean_regen_test-srcs">srcs</a>, <a href="#lean_regen_test-entry">entry</a>, <a href="#lean_regen_test-expected">expected</a>, <a href="#lean_regen_test-out">out</a>, <a href="#lean_regen_test-deps">deps</a>, <a href="#lean_regen_test-data">data</a>, <a href="#lean_regen_test-tags">tags</a>)
</pre>

Assert a committed file matches the current `lean_emit` output.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lean_regen_test-name"></a>name |  target name for the generated diff_test (e.g. `regen_int_arith`). The helper `lean_emit` is named `<name>_emit`.   |  none |
| <a id="lean_regen_test-srcs"></a>srcs |  list of `.lean` source labels needed to compile the entry. Compiled in import-topological order, so list order is irrelevant (a `glob()` is fine). Must include the entry.   |  none |
| <a id="lean_regen_test-entry"></a>entry |  path of the entry-point `.lean` file (relative to the rule's package) defining `main : IO Unit`. Stdout is captured.   |  none |
| <a id="lean_regen_test-expected"></a>expected |  Bazel label of the committed file the lean_emit output is diffed against.   |  none |
| <a id="lean_regen_test-out"></a>out |  optional filename for the emitted artifact (defaults to `<name>_emit.out`).   |  `None` |
| <a id="lean_regen_test-deps"></a>deps |  optional list of `LeanInfo`-providing deps for prebuilt olean closures (passed through to `lean_emit`).   |  `None` |
| <a id="lean_regen_test-data"></a>data |  <p align="center"> - </p>   |  `None` |
| <a id="lean_regen_test-tags"></a>tags |  optional tags propagated to the generated `diff_test` target only.   |  `None` |


