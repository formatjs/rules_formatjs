"""Source inputs large enough to exceed Windows command-line limits."""

def _large_sources_impl(ctx):
    outputs = []
    for index in range(512):
        output = ctx.actions.declare_file("sources with spaces/source_{}.tsx".format(index))
        ctx.actions.expand_template(
            template = ctx.file.src,
            output = output,
            substitutions = {},
        )
        outputs.append(output)
    return [DefaultInfo(files = depset(outputs))]

large_sources = rule(
    implementation = _large_sources_impl,
    attrs = {"src": attr.label(allow_single_file = True, mandatory = True)},
)
