#!/usr/bin/env python3
# Copyright 2025 Snowflake Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Offline render test for the ``ca_yaml_features`` macro.

Renders the real ``macros/ca_yaml_features.sql`` macro with a lightweight,
dbt-compatible Jinja shim (``return()``, package namespace, ``do``, ``tojson``)
so the macro can be exercised without a Snowflake connection or a dbt install.
Only ``jinja2`` is required: ``pip install jinja2``.

Run: ``python scripts/test_ca_yaml_features.py``
"""
import json
import os
import sys

import jinja2

MACRO_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "macros",
    "ca_yaml_features.sql",
)


class MacroReturn(Exception):
    """Mirrors dbt's ``return()`` control flow."""

    def __init__(self, value):
        super().__init__("macro return")
        self.value = value


def _dbt_return(value=None):
    raise MacroReturn(value)


class _Exceptions:
    @staticmethod
    def raise_compiler_error(msg):
        raise RuntimeError(msg)


class _Namespace:
    """Emulates the ``dbt_semantic_view.<macro>`` package namespace, catching the
    MacroReturn a called macro raises and surfacing its value (as dbt does)."""

    def __init__(self, module=None):
        self._module = module

    def bind(self, module):
        self._module = module

    def __getattr__(self, name):
        macro = getattr(self._module, name)

        def _wrapper(*args, **kwargs):
            try:
                return macro(*args, **kwargs)
            except MacroReturn as ret:
                return ret.value

        return _wrapper


def build_namespace():
    env = jinja2.Environment(extensions=["jinja2.ext.do"])
    env.filters["tojson"] = lambda obj: json.dumps(obj)
    env.globals["return"] = _dbt_return
    env.globals["exceptions"] = _Exceptions()
    # The namespace must be visible as a global before the module is built, since
    # the macros reference dbt_semantic_view.* at render time; bind it afterwards.
    namespace = _Namespace()
    env.globals["dbt_semantic_view"] = namespace
    with open(MACRO_FILE, "r", encoding="utf-8") as handle:
        module = env.from_string(handle.read()).module
    namespace.bind(module)
    return namespace


def check(label, condition):
    status = "PASS" if condition else "FAIL"
    print("  [{}] {}".format(status, label))
    return condition


def main():
    ns = build_namespace()

    time_dimensions = [{"table": "orders", "name": "order_ts", "expr": "ORDER_TS", "data_type": "TIMESTAMP_NTZ"}]
    filters = [{"table": "orders", "name": "recent", "expr": "order_ts > dateadd(day, -30, current_date)"}]
    dimensions = [{"table": "orders", "name": "amount", "expr": "AMOUNT", "data_type": "NUMBER(38,2)"}]

    clause = ns.ca_yaml_features(time_dimensions=time_dimensions, filters=filters, dimensions=dimensions)
    print("\nRendered clause:\n" + clause + "\n")

    ok = True
    ok &= check("wrapped in WITH EXTENSION (CA=$$...$$)", clause.startswith("WITH EXTENSION (CA=$$") and clause.endswith("$$)"))

    payload = json.loads(clause[len("WITH EXTENSION (CA=$$"):-len("$$)")])
    table = payload["tables"][0]
    ok &= check("single table 'orders'", len(payload["tables"]) == 1 and table["name"] == "orders")
    ok &= check("time_dimensions carried with data_type", table["time_dimensions"] == time_dimensions_expected())
    ok &= check("standalone filters carried", table["filters"] == [{"name": "recent", "expr": "order_ts > dateadd(day, -30, current_date)"}])
    ok &= check("data_type declared on dimension", table["dimensions"] == [{"name": "amount", "expr": "AMOUNT", "data_type": "NUMBER(38,2)"}])
    ok &= check("routing-only 'table' key stripped from entries", "table" not in table["time_dimensions"][0])

    # Grouping across multiple tables.
    multi = ns.ca_yaml_features(
        time_dimensions=[{"table": "a", "name": "ts", "expr": "TS"}, {"table": "b", "name": "ts2", "expr": "TS2"}],
    )
    multi_payload = json.loads(multi[len("WITH EXTENSION (CA=$$"):-len("$$)")])
    ok &= check("entries grouped by table (a, b)", [t["name"] for t in multi_payload["tables"]] == ["a", "b"])

    # Empty inputs => empty string (safe to always call).
    ok &= check("empty inputs render to ''", ns.ca_yaml_features() == "")

    # Missing 'table' key must raise a clear compiler error.
    raised = False
    try:
        ns.ca_yaml_features(time_dimensions=[{"name": "x", "expr": "X"}])
    except RuntimeError:
        raised = True
    ok &= check("missing 'table' key raises compiler error", raised)

    print("\n" + ("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED"))
    return 0 if ok else 1


def time_dimensions_expected():
    return [{"name": "order_ts", "expr": "ORDER_TS", "data_type": "TIMESTAMP_NTZ"}]


if __name__ == "__main__":
    sys.exit(main())
