"""Catalog collection with optional dependency-triggered source extraction."""

load(":extract.bzl", "FormatjsExtractInfo", "formatjs_extract_action")

FormatjsRuntimeInfo = provider(
    doc = "Marks a runtime dependency that enables FormatJS extraction.",
    fields = [],
)

FormatjsMessagesInfo = provider(
    doc = "Original catalogs and runtime detection propagated by automatic extraction.",
    fields = {
        "catalogs": "Depset of original catalogs; no intermediate merges.",
        "uses_runtime": "Whether a configured dependency enables extraction.",
        "covered_srcs": "Depset of source files represented by explicit extraction metadata.",
        "explicit_catalogs": "Original explicit catalogs, excluding this aspect's extraction actions.",
        "sources_by_repository": "Candidate source depsets grouped by declaring repository.",
    },
)

def _main_repository(_target, ctx):
    return ctx.label.repo_name == ""

def _targets(ctx, attributes):
    result = []
    for attribute in attributes:
        value = getattr(ctx.rule.attr, attribute, [])
        result.extend(value if type(value) == "list" else [value] if value != None else [])
    return result

def _extract_catalogs(ctx, name, sources_by_repository, covered, extensions, options):
    excluded = {source: True for source in covered.to_list()}
    sources = [
        source
        for repository, candidates in sources_by_repository.items()
        for source in candidates.to_list()
        if source.extension in extensions and source.owner.repo_name == repository and source not in excluded
    ]
    if not sources:
        return []
    if not options.get("extract_source_location", False):
        return [formatjs_extract_action(
            ctx,
            sources,
            ctx.actions.declare_file(ctx.label.name + "_" + name + ".json"),
            **options
        ).messages]

    # The CLI keeps only one location for duplicate IDs within a batch.
    catalogs = []
    names = {}
    for source in sources:
        filename = source.basename[:80] + "." + str(hash(source.path)) + ".json"
        if filename in names:
            fail("Extraction output collision between %s and %s" % (source.path, names[filename]))
        names[filename] = source.path
        catalogs.append(formatjs_extract_action(
            ctx,
            [source],
            ctx.actions.declare_file(ctx.label.name + "_" + name + "/" + filename),
            **options
        ).messages)
    return catalogs

def formatjs_message_collector_aspect(
        name = "messages",
        runtime_labels = [],
        is_runtime = None,
        should_extract = _main_repository,
        collect_at = None,
        source_extensions = ["ts", "tsx", "js", "jsx", "mjs", "cjs", "rs", "py"],
        dependency_attributes = ["deps", "srcs"],
        source_attributes = ["srcs"],
        **extraction_options):
    """Creates a collector that can extract sources based on configured dependencies.

    Args:
        name: Unique suffix for this aspect's output files.
        runtime_labels: Label objects for runtime targets that enable extraction.
        is_runtime: Optional predicate (target, ctx) for native providers or
            FormatjsRuntimeInfo. Extraction is disabled when neither is supplied.
        should_extract: Predicate (target, ctx) limiting source owners; defaults
            to targets in the main repository. Collection still crosses others.
        collect_at: Optional predicate (target, ctx) selecting extraction roots for
            rule adapters. Without it, CLI users set --aspects_parameters=formatjs_root=//app:main.
        source_extensions: File extensions without leading dots.
        dependency_attributes: Dependency edges followed for runtime detection
            and catalog collection. Label and label-list attributes work.
        source_attributes: Source attributes; also traversed for extraction metadata.
        **extraction_options: Keyword options accepted by formatjs_extract_action.

    Returns:
        An aspect exposing FormatjsMessagesInfo and all_messages output group.
        Explicit extraction providers remain unchanged on the underlying target.
    """
    if not name:
        fail("formatjs_message_collector_aspect requires a nonempty name")
    for label in runtime_labels:
        if type(label) != "Label":
            fail("runtime_labels must contain Label objects; use Label(...) in the calling .bzl module")
    extraction_enabled = bool(runtime_labels) or is_runtime != None
    attributes = depset(dependency_attributes + source_attributes).to_list()

    def _impl(target, ctx):
        dependencies = [
            dependency[FormatjsMessagesInfo]
            for dependency in _targets(ctx, attributes)
            if FormatjsMessagesInfo in dependency
        ]
        runtime_targets = {runtime.label: True for runtime in ctx.attr._formatjs_runtime_targets}
        uses_runtime = (
            target.label in runtime_targets or
            ctx.label in runtime_targets or
            (is_runtime != None and is_runtime(target, ctx)) or
            any([dependency.uses_runtime for dependency in dependencies])
        )
        explicit_catalogs = depset(
            [target[FormatjsExtractInfo].messages] if FormatjsExtractInfo in target else [],
            transitive = [dependency.explicit_catalogs for dependency in dependencies],
        )
        covered_inputs = [dependency.covered_srcs for dependency in dependencies]
        if FormatjsExtractInfo in target:
            covered_inputs.append(getattr(target[FormatjsExtractInfo], "srcs", depset()))
        covered = depset(transitive = covered_inputs)
        groups = {}
        for dependency in dependencies:
            for repository, sources in dependency.sources_by_repository.items():
                groups.setdefault(repository, []).append(sources)
        if uses_runtime and should_extract(target, ctx):
            groups.setdefault(ctx.label.repo_name, []).extend([
                dependency[DefaultInfo].files
                for dependency in _targets(ctx, source_attributes)
                if DefaultInfo in dependency
            ])
        sources_by_repository = {
            repository: depset(transitive = sources)
            for repository, sources in groups.items()
        }
        catalogs = explicit_catalogs
        if extraction_enabled:
            if collect_at != None:
                is_root = collect_at(target, ctx)
            else:
                if not ctx.attr.formatjs_root:
                    fail("Set --aspects_parameters=formatjs_root=//app:main or configure collect_at")
                is_root = str(ctx.label) == ctx.attr.formatjs_root
            if is_root:
                catalogs = depset(_extract_catalogs(
                    ctx,
                    name,
                    sources_by_repository,
                    covered,
                    source_extensions,
                    extraction_options,
                ), transitive = [explicit_catalogs])
        return [
            FormatjsMessagesInfo(
                catalogs = catalogs,
                uses_runtime = uses_runtime,
                covered_srcs = covered,
                explicit_catalogs = explicit_catalogs,
                sources_by_repository = sources_by_repository,
            ),
            OutputGroupInfo(all_messages = catalogs),
        ]

    attrs = {
        "_formatjs_runtime_targets": attr.label_list(default = runtime_labels, cfg = "target"),
    }
    if extraction_enabled and collect_at == None:
        attrs["formatjs_root"] = attr.string(default = "")
    return aspect(
        implementation = _impl,
        attr_aspects = attributes,
        attrs = attrs,
        toolchains = [Label("//formatjs_cli:toolchain_type")] if extraction_enabled else [],
    )
