"""Consumer-defined rule using the public action helper."""

load("@rules_formatjs//formatjs:defs.bzl", "formatjs_extract_action")

def _extract_impl(ctx):
    info = formatjs_extract_action(ctx, ctx.files.srcs, ctx.outputs.out)
    return [DefaultInfo(files = depset([info.messages])), info]

extract = rule(
    implementation = _extract_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".py"]),
        "out": attr.output(mandatory = True),
    },
    toolchains = ["@rules_formatjs//formatjs_cli:toolchain_type"],
)
