#!/usr/bin/env python3
"""Run pure Kotlin mirror checks using the locally cached Gradle compiler.

No dependency downloads or Android device needed. Missing cache is reported,
not silently treated as a passing check.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path.home() / '.gradle/caches/modules-2/files-2.1'


def jar(group, artifact, version):
    matches = sorted((CACHE / group / artifact / version).glob('*/*.jar'))
    if not matches:
        raise SystemExit(f'Missing cached dependency: {artifact} {version}')
    return str(matches[0])


def compiler():
    std = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.0.0')
    cp = [jar('org.jetbrains.kotlin', name, '2.0.0') for name in (
        'kotlin-compiler-embeddable', 'kotlin-script-runtime', 'kotlin-daemon-embeddable')]
    cp += [std, jar('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
           jar('org.jetbrains.intellij.deps', 'trove4j', '1.0.20200330'),
           jar('org.jetbrains', 'annotations', '13.0')]
    return cp, std


def main():
    cp, std = compiler()
    common = ROOT / 'mirror-common/src'
    sources = list((common / 'main/kotlin').rglob('*.kt'))
    sources += list((common / 'test/kotlin').rglob('*.kt'))
    policy = ROOT / 'car/app/src/debug/java/ai/allo/car/mirror/MirrorDisplayPolicy.kt'
    check = ROOT / 'car/tool/MirrorDisplayPolicyCheck.kt'
    if policy.exists() and check.exists():
        sources += [policy, check]
    mailbox = ROOT / 'phone/android/app/src/debug/kotlin/ai/allo/allo_phone/mirror/LatestFrameBuffer.kt'
    mailbox_check = ROOT / 'phone/tool/mirror_frame_buffer_check.kt'
    sources += [mailbox, mailbox_check]
    with tempfile.TemporaryDirectory(prefix='allo-mirror-kotlin-') as folder:
        subprocess.run(['java', '-cp', os.pathsep.join(cp),
                        'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                        '-no-stdlib', '-no-reflect', '-jvm-target', '17',
                        '-classpath', std, '-d', folder, *map(str, sources)], check=True)
        run_cp = os.pathsep.join([folder, std])
        subprocess.run(['java', '-cp', run_cp, 'ai.allo.mirror.MirrorContractCheckKt'], check=True)
        if policy.exists() and check.exists():
            subprocess.run(['java', '-cp', run_cp, 'ai.allo.car.mirror.MirrorDisplayPolicyCheckKt'], check=True)
        subprocess.run(['java', '-cp', run_cp, 'ai.allo.allo_phone.mirror.Mirror_frame_buffer_checkKt'], check=True)


if __name__ == '__main__':
    main()
