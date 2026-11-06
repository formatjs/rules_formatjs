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

_JQ_TOOLCHAIN = Label("@jq.bzl//jq/toolchain:type")
_SPAWN_TOOLCHAIN = Label("@bazel_lib//lib:spawn_binary_toolchain_type")

_SOURCE_FILTER = """
    ($covered | split("\\n") | map(select(length > 0)) | INDEX(.)) as $excluded
    | $candidates
    | split("\\n")[]
    | select(length > 0)
    | select($excluded[.] == null)
"""

def _source_mapper(repository, extensions):
    def _path(source):
        if source.extension in extensions and source.owner.repo_name == repository:
            return source.path
        return None

    return _path

def _source_list(ctx, name, sources_by_repository, covered, source_extensions):
    excluded = ctx.actions.declare_file(ctx.label.name + "_" + name + ".covered")
    excluded_args = ctx.actions.args()
    excluded_args.add_all(covered)
    excluded_args.set_param_file_format("multiline")
    ctx.actions.write(excluded, excluded_args)

    candidates = ctx.actions.declare_file(ctx.label.name + "_" + name + ".candidates")
    candidate_args = ctx.actions.args()
    for repository, sources in sources_by_repository.items():
        candidate_args.add_all(
            sources,
            map_each = _source_mapper(repository, source_extensions),
            allow_closure = True,
        )
    candidate_args.set_param_file_format("multiline")
    ctx.actions.write(candidates, candidate_args)

    output = ctx.actions.declare_file(ctx.label.name + "_" + name + ".sources")
    jq = ctx.toolchains[_JQ_TOOLCHAIN].jqinfo.bin
    spawn = ctx.toolchains[_SPAWN_TOOLCHAIN].spawn_binary_info.bin
    args = ctx.actions.args()
    args.add("--stdout", output)
    args.add("--")
    args.add(jq)
    args.add_all(["--null-input", "--raw-output", _SOURCE_FILTER])
    args.add("--rawfile")
    args.add("covered")
    args.add(excluded)
    args.add("--rawfile")
    args.add("candidates")
    args.add(candidates)
    ctx.actions.run(
        executable = spawn,
        arguments = [args],
        inputs = [excluded, candidates],
        tools = [jq],
        outputs = [output],
        mnemonic = "FormatjsSourceList",
        toolchain = _SPAWN_TOOLCHAIN,
    )
    return output

def formatjs_message_collector_aspect(
        name = "messages",
        runtime_labels = [],
        is_runtime = None,
        should_extract = _main_repository,
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
        source_extensions: File extensions without leading dots.
        dependency_attributes: Dependency edges followed for runtime detection
            and catalog collection. Label and label-list attributes work.
        source_attributes: Source attributes; also traversed for extraction metadata.
        **extraction_options: Keyword options accepted by formatjs_extract_action.

    Returns:
        An aspect exposing FormatjsMessagesInfo and all_messages output group.
        Newly extracted targets also expose FormatjsExtractInfo.
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
        uses_runtime = (
            target.label in runtime_labels or
            ctx.label in runtime_labels or
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
        sources = depset(transitive = sources_by_repository.values())
        catalogs = explicit_catalogs
        providers = []
        if sources:
            source_list = _source_list(ctx, name, sources_by_repository, covered, source_extensions)
            info = formatjs_extract_action(
                ctx,
                sources,
                ctx.actions.declare_file(ctx.label.name + "_" + name + ".json"),
                source_list = source_list,
                **extraction_options
            )
            catalogs = depset([info.messages], transitive = [explicit_catalogs])
            if FormatjsExtractInfo not in target:
                providers.append(info)
        return providers + [
            FormatjsMessagesInfo(
                catalogs = catalogs,
                uses_runtime = uses_runtime,
                covered_srcs = covered,
                explicit_catalogs = explicit_catalogs,
                sources_by_repository = sources_by_repository,
            ),
            OutputGroupInfo(all_messages = catalogs),
        ]

    return aspect(
        implementation = _impl,
        attr_aspects = attributes,
        toolchains = [Label("//formatjs_cli:toolchain_type"), _JQ_TOOLCHAIN, _SPAWN_TOOLCHAIN] if extraction_enabled else [],
    )
