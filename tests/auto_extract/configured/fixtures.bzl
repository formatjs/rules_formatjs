load("//formatjs:defs.bzl", "FormatjsMessagesInfo", "formatjs_message_collector_aspect")

def _off_impl(_settings, _attr):
    return {"//command_line_option:compilation_mode": "dbg"}

_off = transition(implementation = _off_impl, inputs = [], outputs = ["//command_line_option:compilation_mode"])

def _gen(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".py")
    text = "Allowed" if ctx.attr.scope_allow else "Rejected"
    ctx.actions.write(out, 'from py_intl import define_message\nmessage = define_message(default_message="' + text + '")\n')
    return [DefaultInfo(files = depset([out]))]

generate = rule(implementation = _gen, attrs = {"scope_allow": attr.bool(), "srcs": attr.label_list(allow_files = True)})

def _graph(ctx):
    return [DefaultInfo(files = depset(transitive = [s[DefaultInfo].files for s in ctx.attr.srcs]))]

graph = rule(implementation = _graph, attrs = {"srcs": attr.label_list()})
wrapper = rule(implementation = _graph, attrs = {
    "srcs": attr.label_list(cfg = _off),
    "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
})

def _runtime(_target, ctx):
    return ctx.label.name == "root"

def _scope(_target, ctx):
    return getattr(ctx.rule.attr, "scope_allow", True)

def _root(_target, ctx):
    return ctx.label.name == "root"

messages = formatjs_message_collector_aspect(is_runtime = _runtime, should_extract = _scope, collect_at = _root, extract_source_location = True)

def _catalogs(ctx):
    return [DefaultInfo(files = ctx.attr.target[FormatjsMessagesInfo].catalogs)]

catalogs = rule(implementation = _catalogs, attrs = {"target": attr.label(aspects = [messages])})
