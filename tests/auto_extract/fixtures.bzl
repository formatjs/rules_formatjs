"""Real source graphs for the public automatic extraction API."""

load("//formatjs:defs.bzl", "FormatjsExtractInfo", "FormatjsMessagesInfo", "FormatjsRuntimeInfo", "formatjs_extract_action", "formatjs_message_collector_aspect")

def _graph_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.srcs))]

graph = rule(
    implementation = _graph_impl,
    attrs = {
        "deps": attr.label_list(),
        "srcs": attr.label_list(allow_files = True),
        "runtime": attr.bool(),
        "runtime_dep": attr.label(),
        "source": attr.label(allow_single_file = True),
    },
)

def _runtime_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.srcs)), FormatjsRuntimeInfo()]

runtime = rule(
    implementation = _runtime_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
)

def _metadata_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        ctx.attr.extraction[FormatjsExtractInfo],
    ]

metadata = rule(
    implementation = _metadata_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "extraction": attr.label(providers = [FormatjsExtractInfo]),
    },
)

messages_aspect = formatjs_message_collector_aspect(
    name = "messages",
    runtime_labels = [
        Label("//tests/auto_extract:runtime"),
        Label("//tests/auto_extract:runtime_with_sources"),
    ],
    extract_source_location = True,
    id_interpolation_pattern = "[sha512:contenthash:base64:10]",
)

def _catalogs_impl(ctx):
    return [DefaultInfo(files = ctx.attr.target[FormatjsMessagesInfo].catalogs)]

def _report_impl(ctx):
    info = ctx.attr.target[FormatjsMessagesInfo]
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(output, json.encode({
        "catalogs": sorted([file.basename for file in info.catalogs.to_list()]),
        "sources": sorted([file.basename for file in info.srcs.to_list()]),
        "uses_runtime": info.uses_runtime,
    }))
    return [DefaultInfo(files = depset([output]))]

catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [messages_aspect])},
)

report = rule(
    implementation = _report_impl,
    attrs = {"target": attr.label(aspects = [messages_aspect])},
)

def _adapter_runtime(_target, ctx):
    return getattr(ctx.rule.attr, "runtime", False)

adapter_aspect = formatjs_message_collector_aspect(
    name = "adapter",
    is_runtime = _adapter_runtime,
    source_extensions = ["py"],
)

adapter_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [adapter_aspect])},
)

custom_attributes_aspect = formatjs_message_collector_aspect(
    name = "custom",
    runtime_labels = [Label("//tests/auto_extract:runtime")],
    dependency_attributes = ["runtime_dep"],
    source_attributes = ["source"],
    source_extensions = ["py"],
)

custom_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [custom_attributes_aspect])},
)

def _action_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    info = formatjs_extract_action(
        ctx,
        ctx.files.srcs,
        output,
        extract_source_location = True,
        id_interpolation_pattern = "[sha512:contenthash:base64:10]",
    )
    return [DefaultInfo(files = depset([output])), info]

custom_action = rule(
    implementation = _action_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
    toolchains = ["//formatjs_cli:toolchain_type"],
)

def _scope(_target, ctx):
    return ctx.label.name != "skipped"

scoped_aspect = formatjs_message_collector_aspect(
    name = "scoped",
    runtime_labels = [Label("//tests/auto_extract:runtime")],
    should_extract = _scope,
)

scoped_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [scoped_aspect])},
)

collection_only_aspect = formatjs_message_collector_aspect()

collection_only_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [collection_only_aspect])},
)

unmatched_aspect = formatjs_message_collector_aspect(
    runtime_labels = [Label("//tests/auto_extract:adapter_runtime")],
)

unmatched_report = rule(
    implementation = _report_impl,
    attrs = {"target": attr.label(aspects = [unmatched_aspect])},
)
