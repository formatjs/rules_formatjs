# Dependency-triggered extraction

`formatjs_message_collector_aspect` extracts sources when a configured dependency enables
FormatJS. It follows `deps` and `srcs`, handles aliases and `select()`, and collects
original catalogs in a depset. It registers no intermediate merge actions and adds
no targets to compilation macros.

The ruleset has no dependency on Python, Rust or JavaScript build rules. Runtime
integrations supply `runtime_labels` or an `is_runtime(target, ctx)` predicate.
Labels can differ across consumers; no Intl package name is hardcoded. A predicate
can inspect native providers or a `FormatjsRuntimeInfo` marker.

For example, define `build/i18n.bzl` with your runtime labels:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "formatjs_message_collector_aspect")

rust_messages = formatjs_message_collector_aspect(
    name = "rust_messages",
    runtime_labels = [Label("@my_crates//:formatjs_intl")],
    source_extensions = ["rs"],
    id_interpolation_pattern = "[sha512:contenthash:base64:10]",
    extract_source_location = True,
    flatten = True,
)
```

Runtime labels must be `Label` objects, not strings. Use `Label(...)` in the
calling module so repository mappings resolve there.
Alternatively, `is_runtime(target, ctx)` can recognize a crate or wheel by its
native provider without relying on a particular target label. Either match enables
extraction; detection propagates through configured dependencies.

Without runtime labels or a predicate, the same factory only collects existing
catalogs and requires no CLI toolchain. The existing `message_collector_aspect`
entrypoint uses this configuration.

Then collect messages from an application:

```sh
bazel build //app:main \
  --aspects=//build:i18n.bzl%rust_messages \
  --output_groups=all_messages
```

Detection uses resolved dependencies during analysis, not source imports or
macro-time inspection of dependency labels. Runtime recognition does not require
an implicit dependency on the runtime at every aspect node. A Python adapter can
inspect a wheel's metadata or native provider without configuring that wheel for
unrelated targets.

## Collect at the consumer

Consumers can access `FormatjsMessagesInfo.catalogs` to merge once, applying their
own duplicate-ID and source-location policies:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "FormatjsMessagesInfo")

def _catalogs_impl(ctx):
    return [DefaultInfo(files = ctx.attr.target[FormatjsMessagesInfo].catalogs)]

source_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [rust_messages])},
)
```

`FormatjsMessagesInfo.uses_runtime` carries the detection result;
`FormatjsMessagesInfo.covered_srcs` identifies sources already represented by
explicit extraction metadata. Shared catalogs are deduplicated in the depset. Existing
`FormatjsExtractInfo` catalogs are collected, and their sources are reused rather
than extracted again. Partial metadata excludes only its declared sources;
uncovered files are still extracted. Targets without explicit metadata also expose
`FormatjsExtractInfo` for the automatic catalog.

The aspect carries candidate source depsets by declaring repository and explicit
catalogs through the graph. Each requested root exposes one automatic catalog plus
its explicit catalogs. Parent outputs do not depend on children's automatic
catalogs, so requesting one root runs one automatic extraction. Source lists and
coverage subtraction are materialized at execution, without flattening transitive
coverage during analysis. An empty filtered list produces an empty catalog.

Automatic extraction uses the FormatJS CLI, jq and bazel_lib's `spawn_binary`
toolchains. Filtering runs pinned native executables; no host shell or Python is
used. Collection-only mode requires none of these toolchains. Source artifacts are
declared conservatively as action inputs, including files later excluded by scope,
extension or explicit metadata.

Use one configured aspect for each collection pass. For mixed-language graphs,
combine runtime recognition and source extensions in that aspect. Give each
instantiated aspect a unique `name` to distinguish its output files.

## Scope and options

By default, only targets in the main repository get new extraction actions.
External dependencies can enable extraction, and their explicitly provided catalogs
are still collected, but their raw sources are not automatically scanned. Override
`should_extract(target, ctx)` to change this boundary.

Only files owned by the target's repository are automatically extracted, including
when source labels point into another repository.

`source_extensions` defaults to `ts`, `tsx`, `js`, `jsx`, `mjs`, `cjs`, `rs`, and `py`.
`dependency_attributes` controls dependency traversal; `source_attributes` controls
source inputs and is also traversed for extraction metadata. Both label and
label-list dependency attributes are supported. No extraction action is registered
without runtime detection and eligible, uncovered sources.

Other keyword arguments are the extraction options accepted by
`formatjs_extract_action`, with the same defaults as `formatjs_extract`.

This API collects source messages. Translation archive ownership, locale projection,
catalog merging and runtime installation remain consumer decisions.

## Reuse the extraction action

Custom rules and aspects can register extraction without duplicating CLI arguments,
source response-file handling or toolchain wiring:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "formatjs_extract_action")

def _extract_impl(ctx):
    info = formatjs_extract_action(
        ctx,
        ctx.files.srcs,
        ctx.actions.declare_file(ctx.label.name + ".json"),
        extract_source_location = True,
    )
    return [DefaultInfo(files = depset([info.messages])), info]

extract = rule(
    implementation = _extract_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
    toolchains = ["@rules_formatjs//formatjs_cli:toolchain_type"],
)
```

The caller declares the output and supplies source Files. The helper returns
`FormatjsExtractInfo`; it neither creates a target nor merges catalogs. The existing
`formatjs_extract` rule uses the same helper.
