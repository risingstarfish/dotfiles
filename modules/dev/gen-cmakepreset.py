#!/usr/bin/env python3
"""
Generate CMakeUserPresets.json.

Everything is derived from a few small data tables:

  * SANITISERS - the single sanitisers and which pairs are combined;
  * HOSTS      - the per-host environment profiles;
  * TOOLCHAINS - one entry per compiler. The standard (debug/release)
                 and sanitiser configure/build presets are all derived
                 from these.

Adding a toolchain is a few lines: add one Toolchain(...) to TOOLCHAINS.
Adding a sanitiser is a line or two in SANITISERS (and COMBINED if it
should be available in a combined feature).

Usage:
    gen-cmakepreset.py [OUTPUT_DIR] [--force]

Writes CMakeUserPresets.json into OUTPUT_DIR (default: the current
directory). Errors if the file already exists, unless --force is given.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Sanitisers
# ---------------------------------------------------------------------------
# (name, cache variable, display word)
SANITISERS = [
    ("asan", "SANITIZE_ADDRESS", "address"),
    ("msan", "SANITIZE_MEMORY", "memory"),
    ("tsan", "SANITIZE_THREAD", "thread"),
    ("ubsan", "SANITIZE_UNDEFINED", "undefined"),
]
SINGLE = [name for name, _, _ in SANITISERS]
# Pairs of single sanitisers that make sense combined, as "<a>-<b>".
COMBINED = [
    "asan-ubsan",
    "msan-ubsan",
    "tsan-ubsan",
]
FULL = SINGLE + COMBINED

_WORDS = {name: word for name, _, word in SANITISERS}


@dataclass
class Toolchain:
    name: str
    host: str
    display: str
    description: str
    cc: str
    cxx: str
    sanitizers: list = field(default_factory=list)
    cache: dict = field(default_factory=dict)


TOOLCHAINS = [
    # --- Unix/Linux ---
    Toolchain(
        "unix-clang",
        "host-unix",
        "Clang (Unix)",
        "System Clang on Linux/macOS",
        "$env{SYSTEM}/bin/clang",
        "$env{SYSTEM}/bin/clang++",
        sanitizers=FULL,
    ),
    Toolchain(
        "linux-gcc",
        "host-linux",
        "GCC (Linux)",
        "System GCC on Linux",
        "$env{SYSTEM}/bin/gcc",
        "$env{SYSTEM}/bin/g++",
        sanitizers=FULL,
    ),
    # --- macOS ---
    Toolchain(
        "mac-homebrew-gcc",
        "host-mac",
        "GCC (macOS Brew)",
        "Homebrew GCC on macOS",
        "$env{HOMEBREW_GCC}/bin/gcc-16",
        "$env{HOMEBREW_GCC}/bin/g++-16",
        sanitizers=FULL,
    ),
    Toolchain(
        "mac-homebrew-clang",
        "host-mac",
        "Clang (macOS Brew)",
        "Homebrew Clang on macOS",
        "$env{HOMEBREW_CLANG}/bin/clang",
        "$env{HOMEBREW_CLANG}/bin/clang++",
        sanitizers=FULL,
    ),
    # --- Windows ---
    Toolchain(
        "win-msvc",
        "host-windows",
        "MSVC (Windows)",
        "Visual Studio Compiler",
        "$env{MSVC}/bin/cl.exe",
        "$env{MSVC}/bin/cl.exe",
        sanitizers=["asan"],
    ),
    Toolchain(
        "win-msvc-trunk",
        "host-windows",
        "MSVC Trunk (Windows)",
        "Visual Studio Preview/Trunk Compiler",
        "$env{MSVC_TRUNK}/bin/cl.exe",
        "$env{MSVC_TRUNK}/bin/cl.exe",
        sanitizers=["asan"],
    ),
    Toolchain(
        "win-msvc-llvm",
        "host-windows",
        "MSVC LLVM (Windows)",
        "Clang-cl / LLVM for Windows",
        "$env{MSVC_LLVM}/bin/clang.exe",
        "$env{MSVC_LLVM}/bin/clang++.exe",
        sanitizers=["asan"],
    ),
    Toolchain(
        "win-mingw64",
        "host-windows",
        "MinGW64 (Windows)",
        "GCC on Windows via MinGW64",
        "$env{MINGW64}/bin/gcc.exe",
        "$env{MINGW64}/bin/g++.exe",
        sanitizers=FULL,
    ),
    # --- Trunk / Experimental ---
    Toolchain(
        "unix-gcc-trunk",
        "host-unix",
        "GCC Trunk (Unix)",
        "Latest GCC development snapshot",
        "$env{GCC_TRUNK}/bin/gcc",
        "$env{GCC_TRUNK}/bin/g++",
        sanitizers=FULL,
    ),
    Toolchain(
        "unix-clang-trunk",
        "host-unix",
        "Clang Trunk (Unix)",
        "Latest Clang development snapshot",
        "$env{CLANG_TRUNK}/bin/clang",
        "$env{CLANG_TRUNK}/bin/clang++",
        sanitizers=FULL,
    ),
    Toolchain(
        "unix-clang-p2996",
        "host-unix",
        "Clang P2996 Reflection (Unix)",
        "Experimental C++26 Reflection build",
        "$env{CLANG_P2996}/bin/clang",
        "$env{CLANG_P2996}/bin/clang++",
        cache={
            "CMAKE_CXX_STANDARD": "26",
            "CMAKE_CXX_FLAGS": (
                "-freflection -fexpansion-statements -stdlib=libc++ -std=c++26"
            ),
        },
    ),
    Toolchain(
        "win-gcc-trunk",
        "host-windows",
        "GCC Trunk (Windows)",
        "Latest GCC development snapshot",
        "$env{GCC_TRUNK}/bin/gcc.exe",
        "$env{GCC_TRUNK}/bin/g++.exe",
        sanitizers=FULL,
    ),
    Toolchain(
        "win-clang-trunk",
        "host-windows",
        "Clang Trunk (Windows)",
        "Latest Clang development snapshot",
        "$env{CLANG_TRUNK}/bin/clang.exe",
        "$env{CLANG_TRUNK}/bin/clang++.exe",
        sanitizers=FULL,
    ),
    Toolchain(
        "win-clang-p2996",
        "host-windows",
        "Clang P2996 Reflection (Windows)",
        "Experimental C++26 Reflection build",
        "$env{CLANG_P2996}/bin/clang.exe",
        "$env{CLANG_P2996}/bin/clang++.exe",
        cache={
            "CMAKE_CXX_STANDARD": "26",
            "CMAKE_CXX_FLAGS": (
                "-freflection -fexpansion-statements -stdlib=libc++ -std=c++26"
            ),
        },
    ),
]

# ---------------------------------------------------------------------------
# Host environment profiles
# ---------------------------------------------------------------------------
HOSTS = [
    {
        "name": "host-unix",
        "hidden": True,
        "condition": {
            "type": "inList",
            "string": "${hostSystemName}",
            "list": ["Darwin", "Linux"],
        },
        "environment": {
            "SYSTEM": "/usr",
            "GCC_TRUNK": "$env{HOME}/opt/gcc-trunk",
            "CLANG_TRUNK": "$env{HOME}/opt/clang-trunk",
            "CLANG_P2996": "$env{HOME}/opt/clang-p2996",
        },
    },
    {
        "name": "host-linux",
        "hidden": True,
        "description": "Unix-like OS settings for gcc and clang toolchains",
        "inherits": ["host-unix"],
        "condition": {
            "type": "equals",
            "lhs": "${hostSystemName}",
            "rhs": "Linux",
        },
    },
    {
        "name": "host-mac",
        "hidden": True,
        "description": "macOS settings for gcc and clang toolchains",
        "inherits": ["host-unix"],
        "condition": {
            "type": "equals",
            "lhs": "${hostSystemName}",
            "rhs": "Darwin",
        },
        "environment": {
            "HOMEBREW_CLANG": "/opt/homebrew/opt/llvm",
            "HOMEBREW_GCC": "/opt/homebrew/opt/gcc",
        },
    },
    {
        "name": "host-windows",
        "hidden": True,
        "description": "Windows settings for MSBuild toolchain that apply to msvc and clang",
        "condition": {
            "type": "equals",
            "lhs": "${hostSystemName}",
            "rhs": "Windows",
        },
        "environment": {
            "GCC_TRUNK": "$env{USERPROFILE}/opt/gcc-trunk",
            "CLANG_TRUNK": "$env{USERPROFILE}/opt/clang-trunk",
            "CLANG_P2996": "$env{USERPROFILE}/opt/clang-p2996",
            "MSVC": "$env{USERPROFILE}/opt/msvc",
            "MSVC_TRUNK": "$env{USERPROFILE}/opt/msvc-trunk",
            "MSVC_LLVM": "$env{USERPROFILE}/opt/msvc-llvm",
            "MINGW64": "$env{USERPROFILE}/opt/mingw64",
        },
    },
]

# ---------------------------------------------------------------------------
# Base / build type / feature presets
# ---------------------------------------------------------------------------
BASE = {
    "name": "base",
    "description": "General settings that apply to all configurations",
    "hidden": True,
    "generator": "Ninja",
    "binaryDir": "${sourceDir}/build/${presetName}",
    "installDir": "${sourceDir}/install/${presetName}",
    "cacheVariables": {
        "CMAKE_C_COMPILER_LAUNCHER": "ccache",
        "CMAKE_CXX_COMPILER_LAUNCHER": "ccache",
        "CMAKE_C_STANDARD": "17",
        "CMAKE_C_STANDARD_REQUIRED": "ON",
        "CMAKE_CXX_STANDARD": "23",
        "CMAKE_CXX_STANDARD_REQUIRED": "ON",
        "CMAKE_CXX_EXTENSIONS": "OFF",
        "CMAKE_RUNTIME_OUTPUT_DIRECTORY": "${sourceDir}/build/${presetName}/bin",
        "CMAKE_LIBRARY_OUTPUT_DIRECTORY": "${sourceDir}/build/${presetName}/lib",
        "CMAKE_ARCHIVE_OUTPUT_DIRECTORY": "${sourceDir}/build/${presetName}/lib",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",
        "CMAKE_CXX_SCAN_FOR_MODULES": "OFF",
        # Sanitise
        "SANITIZE_ADDRESS": "OFF",
        "SANITIZE_UNDEFINED": "OFF",
        "SANITIZE_MEMORY": "OFF",
        "SANITIZE_THREAD": "OFF",
    },
}


def _build_type_presets():
    return [
        {
            "name": name,
            "hidden": True,
            "inherits": ["base"],
            "cacheVariables": {"CMAKE_BUILD_TYPE": cfg},
        }
        for name, cfg in (("debug", "Debug"), ("release", "Release"))
    ]


def _feature_presets():
    out = []
    for name, var, word in SANITISERS:
        out.append(
            {
                "name": f"feature-{name}",
                "description": f"Enable {word} sanitiser",
                "hidden": True,
                "cacheVariables": {var: "ON"},
            }
        )
    for name in COMBINED:
        a, b = name.split("-")
        out.append(
            {
                "name": f"feature-{name}",
                "description": f"Enable {a} and {b} sanitisers",
                "hidden": True,
                "inherits": [f"feature-{a}", f"feature-{b}"],
            }
        )
    return out


def _toolchain_presets():
    out = []
    for tc in TOOLCHAINS:
        cache = {
            "CMAKE_C_COMPILER": tc.cc,
            "CMAKE_CXX_COMPILER": tc.cxx,
        }
        cache.update(tc.cache)
        out.append(
            {
                "name": tc.name,
                "hidden": True,
                "inherits": [tc.host],
                "cacheVariables": cache,
            }
        )
    return out


def _standard_configure_presets():
    out = []
    for tc in TOOLCHAINS:
        for cfg in ("Debug", "Release"):
            out.append(
                {
                    "name": f"{tc.name}-{cfg.lower()}",
                    "displayName": f"{tc.display} [{cfg}]",
                    "description": f"{tc.description} - {cfg} build",
                    "inherits": [cfg.lower(), tc.name],
                }
            )
    return out


def _sanitizer_configure_presets():
    out = []
    for tc in TOOLCHAINS:
        for san in tc.sanitizers:
            singles = [p for p in san.split("-") if p in _WORDS]
            words = [_WORDS[s] for s in singles]
            out.append(
                {
                    "name": f"{tc.name}-debug-{san}",
                    "displayName": (
                        f"{tc.display} [Debug]"
                        + "".join(f"[{s.upper()}]" for s in singles)
                    ),
                    "description": (
                        f"{tc.description} with {' and '.join(w.capitalize() for w in words)} "
                        f"{'sanitiser' if len(singles) == 1 else 'sanitisers'}"
                    ),
                    "inherits": ["debug", tc.name] + [f"feature-{s}" for s in singles],
                }
            )
    return out


def _build_presets(configure_presets):
    out = [
        {
            "name": "base-build",
            "hidden": True,
            "jobs": 0,
            "configuration": "Debug",
        }
    ]
    for p in configure_presets:
        if p.get("hidden"):
            continue
        b = {
            "name": p["name"],
            "inherits": "base-build",
            "configurePreset": p["name"],
        }
        if p["name"].endswith("-release"):
            b["configuration"] = "Release"
        out.append(b)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output_dir",
        nargs="?",
        default=".",
        help="directory to write CMakeUserPresets.json into (default: .)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing CMakeUserPresets.json",
    )
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    if not out_dir.is_dir():
        print(f"error: {args.output_dir} is not a directory", file=sys.stderr)
        return 1
    target = out_dir / "CMakeUserPresets.json"
    if target.exists() and not args.force:
        print(
            f"error: {target} already exists; use --force to overwrite",
            file=sys.stderr,
        )
        return 1

    configure_presets = [
        BASE,
        *_build_type_presets(),
        *_feature_presets(),
        *HOSTS,
        *_toolchain_presets(),
        *_standard_configure_presets(),
        *_sanitizer_configure_presets(),
    ]
    build_presets = _build_presets(configure_presets)
    doc = {
        "version": 12,
        "cmakeMinimumRequired": {
            "major": 4,
            "minor": 4,
            "patch": 0,
        },
        "configurePresets": configure_presets,
        "buildPresets": build_presets,
    }
    with open(target, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=4)
        fh.write("\n")
    print(
        f"wrote {target} ({len(configure_presets)} configure, {len(build_presets)} build presets)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
