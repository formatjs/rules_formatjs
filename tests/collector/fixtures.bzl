"""Small extraction-provider graph for exercising the real collector aspect."""

load("//formatjs:aspects.bzl", "message_collector_aspect")
load("//formatjs:extract.bzl", "FormatjsExtractInfo")

def _catalog_impl(ctx):
    catalog = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(catalog, "{}")
    return [
        DefaultInfo(files = depset([catalog])),
        FormatjsExtractInfo(messages = catalog),
    ]

catalog = rule(implementation = _catalog_impl)

def _graph_impl(_ctx):
    return [DefaultInfo(files = depset())]

graph = rule(
    implementation = _graph_impl,
    attrs = {
        "deps": attr.label_list(),
        "srcs": attr.label_list(allow_files = True),
    },
)

def _collected_names_impl(ctx):
    files = ctx.attr.target[OutputGroupInfo].all_messages
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(output, "\n".join(sorted([file.basename for file in files.to_list()])) + "\n")
    return [DefaultInfo(files = depset([output]))]

collected_names = rule(
    implementation = _collected_names_impl,
    attrs = {
        "target": attr.label(aspects = [message_collector_aspect]),
    },
)
