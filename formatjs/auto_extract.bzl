"""Dependency-triggered source extraction without language-rule dependencies."""

load(":extract.bzl", "FormatjsExtractInfo", "formatjs_extract_action")

FormatjsRuntimeInfo = provider(
    doc = "Marks a runtime dependency that enables FormatJS extraction.",
    fields = [],
)

FormatjsAutoExtractInfo = provider(
    doc = "Original catalogs and runtime detection propagated by automatic extraction.",
    fields = {
        "catalogs": "Depset of original catalogs; no intermediate merges.",
        "uses_runtime": "Whether a configured dependency enables extraction.",
        "srcs": "Depset of source files already represented on source edges.",
    },
)

def _marked_runtime(target, _ctx):
    return FormatjsRuntimeInfo in target

def _main_repository(_target, ctx):
    return ctx.label.repo_name == ""

def _targets(ctx, attributes):
    result = []
    for attribute in attributes:
        value = getattr(ctx.rule.attr, attribute, [])
        result.extend(value if type(value) == "list" else [value] if value != None else [])
    return result

def _extracted_sources(target):
    if FormatjsAutoExtractInfo in target:
        return target[FormatjsAutoExtractInfo].srcs
    if FormatjsExtractInfo in target:
        return getattr(target[FormatjsExtractInfo], "srcs", depset())
    return depset()

def formatjs_auto_extract_aspect(
        name,
        is_runtime = _marked_runtime,
        should_extract = _main_repository,
        source_extensions = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "rs", "py"],
        dependency_attributes = ["deps", "srcs"],
        source_attributes = ["srcs"],
        **extraction_options):
    """Creates an extraction/collection aspect enabled by configured dependencies.

    Args:
        name: Unique suffix for this aspect's output files.
        is_runtime: Predicate (target, ctx) identifying the runtime; defaults to
            FormatjsRuntimeInfo. Language adapters can inspect native providers.
        should_extract: Predicate (target, ctx) limiting source owners; defaults
            to targets in the main repository. Collection still crosses others.
        source_extensions: File extensions without leading dots.
        dependency_attributes: Dependency edges followed for runtime detection
            and catalog collection. Label and label-list attributes work.
        source_attributes: Source attributes; also traversed for extraction metadata.
        **extraction_options: Keyword options accepted by formatjs_extract_action.

    Returns:
        An aspect exposing FormatjsAutoExtractInfo and all_messages output group.
        Newly extracted targets also expose FormatjsExtractInfo.
    """
    if not name:
        fail("formatjs_auto_extract_aspect requires a nonempty name")
    attributes = depset(dependency_attributes + source_attributes).to_list()

    def _impl(target, ctx):
        dependencies = [
            dependency[FormatjsAutoExtractInfo]
            for dependency in _targets(ctx, attributes)
            if FormatjsAutoExtractInfo in dependency
        ]
        uses_runtime = is_runtime(target, ctx) or any([dependency.uses_runtime for dependency in dependencies])
        catalogs = []
        providers = []
        covered = depset(transitive = [_extracted_sources(dependency) for dependency in _targets(ctx, source_attributes)])
        own_sources = []
        if FormatjsExtractInfo in target:
            catalogs.append(target[FormatjsExtractInfo].messages)
            covered = depset(transitive = [covered, _extracted_sources(target)])
        elif uses_runtime and should_extract(target, ctx):
            already_extracted = {source: True for source in covered.to_list()}
            own_sources = depset([
                source
                for attribute in source_attributes
                for source in getattr(ctx.rule.files, attribute, [])
                if source.extension in source_extensions and source.owner.repo_name == ctx.label.repo_name and source not in already_extracted
            ]).to_list()
            if own_sources:
                info = formatjs_extract_action(
                    ctx,
                    own_sources,
                    ctx.actions.declare_file(ctx.label.name + "_" + name + ".json"),
                    **extraction_options
                )
                catalogs.append(info.messages)
                providers.append(info)
        all_catalogs = depset(catalogs, transitive = [dependency.catalogs for dependency in dependencies])
        return providers + [
            FormatjsAutoExtractInfo(
                catalogs = all_catalogs,
                uses_runtime = uses_runtime,
                srcs = depset(own_sources, transitive = [covered]),
            ),
            OutputGroupInfo(all_messages = all_catalogs),
        ]

    return aspect(
        implementation = _impl,
        attr_aspects = attributes,
        toolchains = [Label("//formatjs_cli:toolchain_type")],
    )
