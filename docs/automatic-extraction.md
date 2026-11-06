# Dependency-triggered extraction

`formatjs_message_collector_aspect` follows configured `deps` and `srcs`, detects
Intl usage, and carries source plans and explicit catalogs in depsets. Extraction
runs only at selected roots. Libraries do not flatten transitive source sets.

## CLI use

Define `build/i18n.bzl`:

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

Select the extraction root explicitly:

```sh
bazel build //app:main \
  --aspects=//build:i18n.bzl%rust_messages \
  --aspects_parameters=formatjs_root=//app:main \
  --output_groups=all_messages
```

`formatjs_root` must be the actual target's absolute canonical label, not an alias
or relative label. It scopes materialization to that consumer. Other nodes only
propagate source plans and existing catalogs.

Runtime labels must be caller-created `Label` objects. This preserves the caller's
repository mappings. Aliases, including configurable aliases, are resolved in the
target configuration through private resolver dependencies. They are not traversed
for Intl detection, so configuring a resolver does not opt unrelated graphs into
extraction. Their files are not extraction inputs and are not built for detection.
Resolution can configure runtime dependencies in otherwise unrelated graphs; those
configured targets are shared within each configuration.

Alternatively, supply `is_runtime(target, ctx)` to inspect native language providers
or a `FormatjsRuntimeInfo` marker. Predicate-only adapters add no resolver dependency
on the runtime. No language build rules are imported by this ruleset.

## Rule adapters

Rule-propagated aspects use a `collect_at(target, ctx)` predicate instead of the CLI
parameter. Choose application or catalog-consumer roots, not every library:

```starlark
def _at_application(_target, ctx):
    return ctx.label == Label("//app:main")

rust_messages = formatjs_message_collector_aspect(
    name = "rust_messages",
    runtime_labels = [Label("@my_crates//:formatjs_intl")],
    source_extensions = ["rs"],
    collect_at = _at_application,
    extract_source_location = True,
)
```

This configuration also works from the CLI without `--aspects_parameters`.
Consumers access `FormatjsMessagesInfo.catalogs` on a selected root:

```starlark
load("@rules_formatjs//formatjs:defs.bzl", "FormatjsMessagesInfo")

def _catalogs_impl(ctx):
    return [DefaultInfo(files = ctx.attr.target[FormatjsMessagesInfo].catalogs)]

source_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [rust_messages])},
)
```

At intermediate nodes, `catalogs` contains only explicit catalogs. The provider also
exposes `uses_runtime`, `covered_srcs`, `explicit_catalogs`, and source depsets grouped
by declaring repository. A predicate that always returns false gives metadata-only
propagation for adapters that materialize catalogs themselves.

## Catalogs and execution

Roots flatten candidate and covered sources once. Ownership, extension and explicit
coverage filters run before extraction actions are registered. Excluded generated
artifacts are not action inputs, so their producers do not run for catalog builds.
Partial explicit metadata excludes only its declared sources.

Without source locations, uncovered sources use one batch extraction per root.
With `extract_source_location = True`, each file gets its own catalog: the native
CLI keeps only one location for duplicate IDs within a batch. Per-file catalogs
preserve declarations across files and allow unchanged files to reuse cached
extraction actions. Duplicate occurrences within one file retain the native CLI's
behavior. Catalog order is deterministic; no intermediate merge actions are added.
Consumers choose their duplicate-ID and source-location merge policies.

Existing `FormatjsExtractInfo` catalogs are collected unchanged. Automatic outputs
are exposed through `FormatjsMessagesInfo` and `all_messages`; they do not replace
or add a singular `FormatjsExtractInfo` on the underlying target.

Automatic mode requires only the native FormatJS CLI toolchain. No host shell,
Python or filtering toolchain is used. Without runtime labels or a predicate, the
factory only collects existing catalogs and requires no CLI toolchain. The existing
`message_collector_aspect` entrypoint keeps that collection-only behavior.

## Scope and options

By default, only targets in the main repository contribute new source candidates.
External dependencies can enable extraction and provide explicit catalogs without
having their implementation scanned. Override `should_extract(target, ctx)` to
change that target boundary. Only files owned by a contributing target's repository
are eligible, including when source labels point into another repository.

`source_extensions` defaults to `ts`, `tsx`, `js`, `jsx`, `mjs`, `cjs`, `rs`, and `py`.
`dependency_attributes` controls detection/collection edges; `source_attributes`
controls source inputs and is also traversed for extraction metadata. Both label
and label-list attributes work. Aliases and `select()` are handled after resolution.

Other keyword arguments are options accepted by `formatjs_extract_action`.
Use one configured aspect per collection pass. Mixed-language adapters can combine
runtime recognition and source extensions in that aspect. Give separate instances
unique `name` values to distinguish output files.

Archive ownership, translation projection, catalog merging and runtime installation
remain consumer decisions.

## Custom extraction actions

`formatjs_extract_action(ctx, srcs, out, **options)` registers the native action and
returns `FormatjsExtractInfo`. `srcs` accepts a list or depset of source Files; the
caller declares the output and CLI toolchain. The existing `formatjs_extract` rule
uses the same helper, including its options and response-file handling.
