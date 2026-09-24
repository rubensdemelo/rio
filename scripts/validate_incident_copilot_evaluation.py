#!/usr/bin/env python3
"""Validate the synthetic Rio incident-copilot evaluation pack."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = ROOT / "docs/evaluation/incident-copilot-mvp/scenarios.json"
PACK_KEYS = {
    "schema_version",
    "pack_id",
    "synthetic_only",
    "purpose",
    "allowed_signal_types",
    "scenarios",
}
SIGNAL_GROUPS = {
    "symptoms",
    "errors",
    "product_version_environment_facts",
    "recent_changes",
    "failed_checks",
    "unanswered_diagnostic_questions",
}
ALLOWED_SIGNAL_TYPES = {
    "symptom",
    "error",
    "product_version_environment_fact",
    "recent_change",
    "failed_check",
    "unanswered_diagnostic_question",
}
REQUIRED_SCENARIO_KEYS = {
    "id",
    "track",
    "title",
    "consent",
    "call",
    "expected_incident_signals",
    "expected_retrieval_intent",
    "expected_possible_directions",
    "expected_evidence_characteristics",
    "expected_next_questions",
    "forbidden_behaviors",
}


def fail(message: str) -> None:
    raise ValueError(message)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def require_object(value: object, path: str) -> dict:
    require(isinstance(value, dict), f"{path} must be an object")
    return value


def require_list(value: object, path: str) -> list:
    require(isinstance(value, list), f"{path} must be a list")
    return value


def require_exact_keys(value: dict, expected: set[str], path: str) -> None:
    actual = set(value)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    details = []
    if missing:
        details.append(f"missing {missing}")
    if unexpected:
        details.append(f"unexpected {unexpected}")
    require(not details, f"{path} has invalid keys: {', '.join(details)}")


def require_string(value: object, path: str) -> str:
    require(isinstance(value, str), f"{path} must be a string")
    require(bool(value.strip()), f"{path} must not be empty")
    return value


def require_string_list(value: object, path: str, *, nonempty: bool = False) -> list[str]:
    items = require_list(value, path)
    if nonempty:
        require(bool(items), f"{path} must not be empty")
    strings = []
    for index, item in enumerate(items):
        strings.append(require_string(item, f"{path}[{index}]"))
    require(len(strings) == len(set(strings)), f"{path} must not contain duplicates")
    return strings


def require_bool(value: object, path: str) -> bool:
    require(type(value) is bool, f"{path} must be a boolean")
    return value


def require_int(value: object, path: str) -> int:
    require(type(value) is int, f"{path} must be an integer")
    return value


def validate_turns(scenario: dict) -> None:
    scenario_id = scenario["id"]
    call = require_object(scenario["call"], f"{scenario_id}.call")
    require_exact_keys(call, {"context", "turns"}, f"{scenario_id}.call")
    require_string(call["context"], f"{scenario_id}.call.context")
    turns = require_list(call["turns"], f"{scenario_id}.call.turns")
    require(bool(turns), f"{scenario_id}.call.turns must not be empty")

    numbers = []
    for index, raw_turn in enumerate(turns):
        path = f"{scenario_id}.call.turns[{index}]"
        turn = require_object(raw_turn, path)
        require_exact_keys(turn, {"turn", "speaker", "text"}, path)
        numbers.append(require_int(turn["turn"], f"{path}.turn"))
        require_string(turn["speaker"], f"{path}.speaker")
        require_string(turn["text"], f"{path}.text")
    require(numbers == list(range(1, len(turns) + 1)), f"{scenario_id}: turns must be contiguous and start at 1")


def validate_signal_groups(scenario: dict) -> set[str]:
    scenario_id = scenario["id"]
    signals = require_object(scenario["expected_incident_signals"], f"{scenario_id}.expected_incident_signals")
    require_exact_keys(signals, SIGNAL_GROUPS, f"{scenario_id}.expected_incident_signals")
    turn_count = len(scenario["call"]["turns"])
    signal_ids = set()

    for group, raw_entries in signals.items():
        entries = require_list(raw_entries, f"{scenario_id}.expected_incident_signals.{group}")
        for index, raw_entry in enumerate(entries):
            path = f"{scenario_id}.expected_incident_signals.{group}[{index}]"
            entry = require_object(raw_entry, path)
            require_exact_keys(entry, {"id", "text", "source_turns"}, path)
            signal_id = require_string(entry["id"], f"{path}.id")
            require(
                signal_id not in signal_ids,
                f'{scenario_id}: duplicate signal id "{signal_id}" across signal groups',
            )
            signal_ids.add(signal_id)
            require_string(entry["text"], f"{path}.text")

            source_turns = require_list(entry["source_turns"], f"{path}.source_turns")
            require(bool(source_turns), f"{path}.source_turns must not be empty")
            validated_turns = [
                require_int(number, f"{path}.source_turns[{turn_index}]")
                for turn_index, number in enumerate(source_turns)
            ]
            require(
                len(validated_turns) == len(set(validated_turns)),
                f"{path}.source_turns must not contain duplicates",
            )
            require(
                all(1 <= number <= turn_count for number in validated_turns),
                f"{path}.source_turns contains a turn outside 1...{turn_count}",
            )
    return signal_ids


def validate_retrieval(scenario: dict, signal_ids: set[str]) -> None:
    scenario_id = scenario["id"]
    intents = require_list(scenario["expected_retrieval_intent"], f"{scenario_id}.expected_retrieval_intent")
    intent_ids = set()
    for index, raw_intent in enumerate(intents):
        path = f"{scenario_id}.expected_retrieval_intent[{index}]"
        intent = require_object(raw_intent, path)
        require_exact_keys(intent, {"id", "intent", "preferred_terms", "must_preserve", "avoid"}, path)
        intent_id = require_string(intent["id"], f"{path}.id")
        require(intent_id not in intent_ids, f'{scenario_id}: duplicate retrieval intent id "{intent_id}"')
        intent_ids.add(intent_id)
        texts = [require_string(intent["intent"], f"{path}.intent")]
        texts.extend(require_string_list(intent["preferred_terms"], f"{path}.preferred_terms", nonempty=True))
        texts.extend(require_string_list(intent["must_preserve"], f"{path}.must_preserve"))
        texts.extend(require_string_list(intent["avoid"], f"{path}.avoid"))
        for text in texts:
            parsed = urlparse(text)
            require(not parsed.scheme and not parsed.netloc, f"{path} must not contain an external URL")

    evidence_path = f"{scenario_id}.expected_evidence_characteristics"
    evidence = require_object(scenario["expected_evidence_characteristics"], evidence_path)
    required_evidence_keys = {
        "authoritative_source_types",
        "minimum_sources",
        "required_provenance",
        "must_support",
        "acceptable_gaps",
    }
    require_exact_keys(evidence, required_evidence_keys, evidence_path)
    require_string_list(evidence["authoritative_source_types"], f"{evidence_path}.authoritative_source_types")
    minimum_sources = require_int(evidence["minimum_sources"], f"{evidence_path}.minimum_sources")
    require(minimum_sources >= 0, f"{evidence_path}.minimum_sources must not be negative")
    required_provenance = require_string_list(evidence["required_provenance"], f"{evidence_path}.required_provenance")
    require(
        minimum_sources == 0 or bool(required_provenance),
        f"{evidence_path}.required_provenance is required when sources are expected",
    )
    require_string_list(evidence["must_support"], f"{evidence_path}.must_support")
    require_string_list(evidence["acceptable_gaps"], f"{evidence_path}.acceptable_gaps")

    directions = require_list(scenario["expected_possible_directions"], f"{scenario_id}.expected_possible_directions")
    direction_ids = set()
    for index, raw_direction in enumerate(directions):
        path = f"{scenario_id}.expected_possible_directions[{index}]"
        direction = require_object(raw_direction, path)
        require_exact_keys(direction, {"id", "statement", "grounded_by"}, path)
        direction_id = require_string(direction["id"], f"{path}.id")
        require(direction_id not in direction_ids, f'{scenario_id}: duplicate possible-direction id "{direction_id}"')
        direction_ids.add(direction_id)
        require_string(direction["statement"], f"{path}.statement")
        grounded_by = require_string_list(direction["grounded_by"], f"{path}.grounded_by", nonempty=True)
        unknown_ids = sorted(set(grounded_by) - signal_ids)
        require(not unknown_ids, f"{path}.grounded_by references unknown signal ids {unknown_ids}")


def validate_questions(scenario: dict) -> None:
    scenario_id = scenario["id"]
    questions = require_list(scenario["expected_next_questions"], f"{scenario_id}.expected_next_questions")
    ids = set()
    for index, raw_question in enumerate(questions):
        path = f"{scenario_id}.expected_next_questions[{index}]"
        question = require_object(raw_question, path)
        require_exact_keys(question, {"id", "question", "why", "priority"}, path)
        question_id = require_string(question["id"], f"{path}.id")
        require(question_id not in ids, f'{scenario_id}: duplicate next-question id "{question_id}"')
        ids.add(question_id)
        question_text = require_string(question["question"], f"{path}.question")
        require(question_text.endswith("?"), f"{path}.question must end with ?")
        require_string(question["why"], f"{path}.why")
        priority = require_int(question["priority"], f"{path}.priority")
        require(priority >= 1, f"{path}.priority must be positive")


def validate_forbidden_behaviors(scenario: dict) -> None:
    scenario_id = scenario["id"]
    require_string_list(
        scenario["forbidden_behaviors"],
        f"{scenario_id}.forbidden_behaviors",
        nonempty=True,
    )


def validate_pack(raw_pack: object) -> dict:
    pack = require_object(raw_pack, "evaluation pack")
    require_exact_keys(pack, PACK_KEYS, "evaluation pack")
    require(pack["schema_version"] == "1.0", 'evaluation pack.schema_version must be "1.0"')
    require_string(pack["pack_id"], "evaluation pack.pack_id")
    require_bool(pack["synthetic_only"], "evaluation pack.synthetic_only")
    require(pack["synthetic_only"] is True, "evaluation pack.synthetic_only must be true")
    require_string(pack["purpose"], "evaluation pack.purpose")
    allowed_signal_types = require_string_list(pack["allowed_signal_types"], "evaluation pack.allowed_signal_types")
    require(
        set(allowed_signal_types) == ALLOWED_SIGNAL_TYPES,
        "evaluation pack.allowed_signal_types does not match the supported signal types",
    )

    scenarios = require_list(pack["scenarios"], "evaluation pack.scenarios")
    require(len(scenarios) == 6, "evaluation pack.scenarios must contain six representative scenarios")
    validated_scenarios = []
    ids = set()
    tracks = set()
    for index, raw_scenario in enumerate(scenarios):
        path = f"evaluation pack.scenarios[{index}]"
        scenario = require_object(raw_scenario, path)
        require_exact_keys(scenario, REQUIRED_SCENARIO_KEYS, path)
        scenario_id = require_string(scenario["id"], f"{path}.id")
        require(scenario_id not in ids, f'duplicate scenario id "{scenario_id}"')
        ids.add(scenario_id)
        track = require_string(scenario["track"], f"{scenario_id}.track")
        require(
            track in {"incident", "privacy-consent"},
            f'{scenario_id}.track must be "incident" or "privacy-consent"',
        )
        tracks.add(track)
        require_string(scenario["title"], f"{scenario_id}.title")

        consent = require_object(scenario["consent"], f"{scenario_id}.consent")
        require_exact_keys(consent, {"required", "given_in_scenario", "expected_if_missing"}, f"{scenario_id}.consent")
        require_bool(consent["required"], f"{scenario_id}.consent.required")
        require(consent["required"] is True, f"{scenario_id}.consent.required must be true")
        require_bool(consent["given_in_scenario"], f"{scenario_id}.consent.given_in_scenario")
        expected_if_missing = require_string(
            consent["expected_if_missing"],
            f"{scenario_id}.consent.expected_if_missing",
        )
        require(
            expected_if_missing == "do_not_process_or_retrieve",
            f"{scenario_id}.consent.expected_if_missing must be do_not_process_or_retrieve",
        )

        validate_turns(scenario)
        signal_ids = validate_signal_groups(scenario)
        validate_retrieval(scenario, signal_ids)
        validate_questions(scenario)
        validate_forbidden_behaviors(scenario)
        if track == "incident" and consent["given_in_scenario"]:
            require(
                bool(signal_ids),
                f"{scenario_id}: consent-given incident scenario must have expected incident signals",
            )
            require(
                bool(scenario["expected_retrieval_intent"]),
                f"{scenario_id}: consent-given incident scenario must have retrieval intent",
            )
            require(
                bool(scenario["expected_possible_directions"]),
                f"{scenario_id}: consent-given incident scenario must have possible directions",
            )
            require(
                bool(scenario["expected_next_questions"]),
                f"{scenario_id}: consent-given incident scenario must have next questions",
            )
        validated_scenarios.append(scenario)

    require(
        "incident" in tracks and "privacy-consent" in tracks,
        "evaluation pack must cover incident and privacy-consent tracks",
    )
    denied = [scenario for scenario in validated_scenarios if not scenario["consent"]["given_in_scenario"]]
    require(len(denied) == 1, "evaluation pack must contain exactly one consent-denied scenario")
    denied_id = denied[0]["id"]
    require(
        denied[0]["track"] == "privacy-consent",
        f'{denied_id}: consent-denied scenario must use the "privacy-consent" track',
    )
    require(
        all(not entries for entries in denied[0]["expected_incident_signals"].values()),
        f"{denied_id}: consent-denied scenario must have no extracted incident signals",
    )
    require(
        not denied[0]["expected_retrieval_intent"],
        f"{denied_id}: consent-denied scenario must have no retrieval intent",
    )
    require(
        not denied[0]["expected_possible_directions"],
        f"{denied_id}: consent-denied scenario must have no possible directions",
    )
    require(
        not denied[0]["expected_next_questions"],
        f"{denied_id}: consent-denied scenario must have no next questions",
    )
    return pack


def main() -> int:
    try:
        pack = validate_pack(json.loads(PACK_PATH.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"incident-copilot evaluation pack: FAIL: {error}", file=sys.stderr)
        return 1
    print(f"incident-copilot evaluation pack: PASS ({len(pack['scenarios'])} synthetic scenarios)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
