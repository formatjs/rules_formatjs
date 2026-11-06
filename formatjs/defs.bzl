"""Public API for FormatJS Bazel rules

This module provides the main entry points for using FormatJS in Bazel builds.
"""

load(
    ":aggregate.bzl",
    _FormatjsAggregateInfo = "FormatjsAggregateInfo",
    _formatjs_aggregate = "formatjs_aggregate",
    _formatjs_aggregate_aspect = "formatjs_aggregate_aspect",
)
load(
    ":collector.bzl",
    _FormatjsMessagesInfo = "FormatjsMessagesInfo",
    _FormatjsRuntimeInfo = "FormatjsRuntimeInfo",
    _formatjs_message_collector_aspect = "formatjs_message_collector_aspect",
)
load(":compile.bzl", _formatjs_compile = "formatjs_compile")
load(":extract.bzl", _FormatjsExtractInfo = "FormatjsExtractInfo", _formatjs_extract = "formatjs_extract", _formatjs_extract_action = "formatjs_extract_action")
load(":verify.bzl", _formatjs_verify_test = "formatjs_verify_test")

# Public API - Rules
formatjs_extract = _formatjs_extract
formatjs_compile = _formatjs_compile
formatjs_aggregate = _formatjs_aggregate
formatjs_verify_test = _formatjs_verify_test

# Public API - Aspects
formatjs_aggregate_aspect = _formatjs_aggregate_aspect

# Public API - Providers
FormatjsExtractInfo = _FormatjsExtractInfo
FormatjsAggregateInfo = _FormatjsAggregateInfo

# Public API - Rule/aspect integration
formatjs_extract_action = _formatjs_extract_action
formatjs_message_collector_aspect = _formatjs_message_collector_aspect
FormatjsMessagesInfo = _FormatjsMessagesInfo
FormatjsRuntimeInfo = _FormatjsRuntimeInfo
