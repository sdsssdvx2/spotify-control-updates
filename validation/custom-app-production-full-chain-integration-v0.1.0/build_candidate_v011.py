from __future__ import annotations
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'build_candidate.py'
EXPECTED_SOURCE_BLOB = '285708ed5d86be572cf40804f34d3e8dcbae6ade'
EXPECTED_OVERRIDES = {
    'Get-CustomAppProductionConsumptionEnvelopeMaterialV010',
    'New-CustomAppProductionConsumptionEnvelopeV010',
    'Test-CustomAppProductionConsumptionEnvelopeV010',
    'Test-CustomAppProductionTransactionFinalizationResultV010',
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label} patch anchor drift: {count}')
    return text.replace(old, new, 1)


def patched_source() -> str:
    actual = subprocess.check_output(['git','hash-object',str(SOURCE)], text=True).strip()
    if actual != EXPECTED_SOURCE_BLOB:
        raise RuntimeError(f'v0.1.0 integration builder drift: {actual} != {EXPECTED_SOURCE_BLOB}')
    text = SOURCE.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "# The cleanup receipt overlay intentionally replaces exactly this earlier validator.\nALLOWED_OVERRIDES = {'Test-CustomAppProductionTransactionFinalizationResultV010'}",
        "# Exact validated hardening overlays. No other function collision is permitted.\nEXPECTED_OVERRIDES = {\n"
        "    'Get-CustomAppProductionConsumptionEnvelopeMaterialV010',\n"
        "    'New-CustomAppProductionConsumptionEnvelopeV010',\n"
        "    'Test-CustomAppProductionConsumptionEnvelopeV010',\n"
        "    'Test-CustomAppProductionTransactionFinalizationResultV010',\n"
        "}\nALLOWED_OVERRIDES = EXPECTED_OVERRIDES",
        'override declaration',
    )
    text = replace_once(
        text,
        '    chunks=[]; override_count=0; module_report=[]',
        '    chunks=[]; actual_overrides=[]; module_report=[]',
        'override accumulator',
    )
    text = replace_once(
        text,
        '        override_count += len(allowed)',
        '        actual_overrides.extend(allowed)',
        'override recording',
    )
    text = replace_once(
        text,
        "    if override_count != 1:\n        raise RuntimeError(f'intentional override count drift: {override_count} != 1')",
        "    if len(actual_overrides) != len(EXPECTED_OVERRIDES) or set(actual_overrides) != EXPECTED_OVERRIDES:\n"
        "        raise RuntimeError(f'intentional override set drift: {sorted(actual_overrides)} != {sorted(EXPECTED_OVERRIDES)}')",
        'override exact-set assertion',
    )
    text = replace_once(
        text,
        "    return bom+text.encode('utf-8'), {'modules':module_report,'base_function_count':len(base_function_names),'intentional_override_count':override_count,'normal_path_leaks':leaks}",
        "    return bom+text.encode('utf-8'), {'modules':module_report,'base_function_count':len(base_function_names),'intentional_override_count':len(actual_overrides),'intentional_overrides':sorted(actual_overrides),'normal_path_leaks':leaks}",
        'override report',
    )
    return text


def main() -> None:
    source = patched_source()
    fake = HERE / '_patched_full_chain_builder_v011.py'
    ns = {'__file__': str(fake), '__name__': 'custom_app_production_full_chain_integration_v011'}
    exec(compile(source, str(fake), 'exec'), ns)
    ns['build']()


if __name__ == '__main__':
    main()
