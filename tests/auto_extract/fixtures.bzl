"""Real source graphs for the public automatic extraction API."""

load("//formatjs:defs.bzl", "FormatjsExtractInfo", "FormatjsMessagesInfo", "FormatjsRuntimeInfo", "formatjs_extract_action", "formatjs_message_collector_aspect")

def _graph_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [source[DefaultInfo].files for source in ctx.attr.srcs]))]

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
        "deps": attr.label_list(),
    },
)

def _collect_at(_target, ctx):
    return ctx.label.name in [
        "root",
        "leaf",
        "plain",
        "unsupported",
        "adapter_source",
        "custom_attributes",
        "skipped",
        "partial_metadata",
        "chain_99",
        "consumer",
        "shared_root",
        "with_ignored",
        "leaf_select",
        "scope_wrapper_root",
        "scope_direct_root",
        "collision_root",
    ]

messages_aspect = formatjs_message_collector_aspect(
    name = "messages",
    collect_at = _collect_at,
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
        "catalog_count": len(info.catalogs.to_list()),
        "sources": sorted([file.basename for file in info.covered_srcs.to_list()]),
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
    collect_at = _collect_at,
    is_runtime = _adapter_runtime,
    source_extensions = ["py"],
)

adapter_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [adapter_aspect])},
)

custom_attributes_aspect = formatjs_message_collector_aspect(
    name = "custom",
    collect_at = _collect_at,
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
    return ctx.label.name not in ["skipped", "skipped_generated", "skipped_generated_wrapper"]

scoped_aspect = formatjs_message_collector_aspect(
    name = "scoped",
    collect_at = _collect_at,
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
    collect_at = _collect_at,
    runtime_labels = [Label("//tests/auto_extract:ignored_generated")],
)

unmatched_report = rule(
    implementation = _report_impl,
    attrs = {"target": attr.label(aspects = [unmatched_aspect])},
)

def _python_source_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".py")
    ctx.actions.write(output, "from py_intl import define_message\nmessage = define_message(default_message=%s)\n" % json.encode(ctx.label.name))
    return [DefaultInfo(files = depset([output]))]

python_source = rule(implementation = _python_source_impl)

def source_chain(name, count):
    for index in range(count):
        python_source(name = name + "_source_" + str(index))
        graph(
            name = name + "_" + str(index),
            srcs = [":" + name + "_source_" + str(index)] + ([":" + name + "_" + str(index - 1)] if index else []),
            deps = [] if index else [":runtime"],
        )
    catalogs(name = name + "_catalogs", target = ":" + name + "_" + str(count - 1))
    report(name = name + "_report", target = ":" + name + "_" + str(count - 1))

alias_aspect = formatjs_message_collector_aspect(
    runtime_labels = [Label("//tests/auto_extract:runtime_alias")],
    collect_at = _collect_at,
)

alias_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [alias_aspect])},
)

def _ignored_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.run_shell(outputs = [output], command = "exit 1", mnemonic = "IgnoredProducer")
    return [DefaultInfo(files = depset([output]))]

ignored = rule(implementation = _ignored_impl)

cli_aspect = formatjs_message_collector_aspect(
    runtime_labels = [Label("//tests/auto_extract:runtime_alias"), Label("//tests/auto_extract:runtime_with_sources")],
    extract_source_location = True,
)

selected_alias_aspect = formatjs_message_collector_aspect(
    runtime_labels = [Label("//tests/auto_extract:runtime_selected_alias")],
    collect_at = _collect_at,
)

selected_alias_catalogs = rule(
    implementation = _catalogs_impl,
    attrs = {"target": attr.label(aspects = [selected_alias_aspect])},
)

batch_aspect = formatjs_message_collector_aspect(
    name = "batch",
    runtime_labels = [Label("//tests/auto_extract:runtime_alias")],
    collect_at = _collect_at,
)

batch_catalogs = rule(implementation = _catalogs_impl, attrs = {"target": attr.label(aspects = [batch_aspect])})
batch_report = rule(implementation = _report_impl, attrs = {"target": attr.label(aspects = [batch_aspect])})
