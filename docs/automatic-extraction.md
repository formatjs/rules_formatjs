# Dependency-triggered extraction

`formatjs_auto_extract_aspect` extracts sources when a configured dependency enables
FormatJS. It follows `deps` and `srcs`, handles aliases and `select()`, and collects
original catalogs in a depset. It registers no intermediate merge actions and adds
no targets to compilation macros.

The ruleset has no dependency on Python, Rust or JavaScript build rules. Runtime
integrations can return `FormatjsRuntimeInfo()` from their native rule. For external
runtimes, supply a predicate that recognizes the language's native provider.

For example, a Rust consumer can define `build/i18n.bzl`:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "formatjs_auto_extract_aspect")
load("@rules_rust//rust:defs.bzl", "rust_common")

def _rust_runtime(target, _ctx):
    return (
        rust_common.crate_info in target and
        target[rust_common.crate_info].name == "formatjs_intl"
    )

rust_messages = formatjs_auto_extract_aspect(
    name = "rust_messages",
    is_runtime = _rust_runtime,
    source_extensions = ["rs"],
    id_interpolation_pattern = "[sha512:contenthash:base64:10]",
    extract_source_location = True,
    flatten = True,
)
```

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

Consumers can access `FormatjsAutoExtractInfo.catalogs` to merge once, applying their
own duplicate-ID and source-location policies:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "FormatjsAutoExtractInfo")

def _catalogs_impl(ctx):
    return [DefaultInfo(files = ctx.attr.target[FormatjsAutoExtractInfo].catalogs)]

source_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [rust_messages])},
)
```

`FormatjsAutoExtractInfo.uses_runtime` carries the detection result;
`FormatjsAutoExtractInfo.srcs` identifies sources already represented on source
edges. Shared catalogs are deduplicated in the depset. Existing
`FormatjsExtractInfo` catalogs are collected, and their sources are reused rather
than extracted again. Newly extracted targets also expose `FormatjsExtractInfo`.

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
