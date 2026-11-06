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
    },
)

_SourcePlansInfo = provider(fields = ["catalogs", "covered", "plan", "plans"])

def _main_repository(_target, ctx):
    return ctx.label.repo_name == ""

def _targets(ctx, attributes):
    result = []
    for attribute in attributes:
        value = getattr(ctx.rule.attr, attribute, [])
        result.extend(value if type(value) == "list" else [value] if value != None else [])
    return result

def _source_path(source):
    return source.path

def _source_files(plans, covered, extensions):
    requested = {}
    candidates = {}
    direct = []
    owners = {}

    # Parents request source views before their children are visited. Each
    # configured node is visited once, even through shared source wrappers.
    for plan in plans.to_list()[::-1]:
        if not plan.allowed or not (plan.enabled or plan.key in requested):
            continue
        if plan.key in requested:
            owners[plan.key] = True
        for source in plan.sources:
            if plan.enabled:
                candidates.setdefault(plan.key[0].repo_name, []).append(source.files)
            if source.key == None:
                direct.append(source.files)
            else:
                requested[source.key] = True
    eligible = {source: True for source in depset(transitive = direct).to_list()}
    excluded = {source: True for source in covered.to_list()}
    return [
        source
        for repository, inputs in candidates.items()
        for source in depset(transitive = inputs).to_list()
        if source.extension in extensions and source.owner.repo_name == repository and source not in excluded and (
            source in eligible or (source.owner, source.root.path) in owners
        )
    ]

def _extract_catalogs(ctx, name, sources, options):
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
        filename = source.basename[:80] + "." + str(hash(source.path))
        names.setdefault(filename, []).append(source)
    for filename, files in names.items():
        # Disambiguate hash collisions without lengthening every source path.
        for index, source in enumerate(sorted(files, key = _source_path) if len(files) > 1 else files):
            suffix = "_" + str(index) if len(files) > 1 else ""
            catalogs.append(formatjs_extract_action(
                ctx,
                [source],
                ctx.actions.declare_file(ctx.label.name + "_" + name + "/" + filename + suffix + ".json"),
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
        dependencies = _targets(ctx, attributes)
        inherited = [dependency[_SourcePlansInfo] for dependency in dependencies if _SourcePlansInfo in dependency]
        runtime_targets = {runtime.label: True for runtime in ctx.attr._formatjs_runtime_targets}
        uses_runtime = (
            target.label in runtime_targets or
            ctx.label in runtime_targets or
            (is_runtime != None and is_runtime(target, ctx)) or
            any([dependency[FormatjsMessagesInfo].uses_runtime for dependency in dependencies if FormatjsMessagesInfo in dependency])
        )
        explicit_catalogs = depset(
            [target[FormatjsExtractInfo].messages] if FormatjsExtractInfo in target else [],
            transitive = [dependency.catalogs for dependency in inherited],
        )
        covered = depset(
            transitive = [dependency.covered for dependency in inherited] + (
                [getattr(target[FormatjsExtractInfo], "srcs", depset())] if FormatjsExtractInfo in target else []
            ),
        )
        plan = None
        if extraction_enabled:
            allowed = should_extract(target, ctx)

            # Labels alone conflate generators reached through transitions.
            plan = struct(
                key = (target.label, ctx.bin_dir.path),
                allowed = allowed,
                enabled = allowed and uses_runtime,
                sources = tuple([
                    struct(
                        key = dependency[_SourcePlansInfo].plan.key if _SourcePlansInfo in dependency else None,
                        files = dependency[DefaultInfo].files,
                    )
                    for dependency in _targets(ctx, source_attributes)
                    if DefaultInfo in dependency
                ]),
            )
        plans = depset(
            [plan] if plan != None else [],
            transitive = [dependency.plans for dependency in inherited],
            order = "postorder",
        )
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
                    _source_files(plans, covered, source_extensions),
                    extraction_options,
                ), transitive = [explicit_catalogs])
        return [
            FormatjsMessagesInfo(
                catalogs = catalogs,
                uses_runtime = uses_runtime,
            ),
            _SourcePlansInfo(catalogs = explicit_catalogs, covered = covered, plan = plan, plans = plans),
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
