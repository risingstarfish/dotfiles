//   _____        _    __ _ _
//  |  __ \      | |  / _(_) |
//  | |  | | ___ | |_| |_ _| | ___  ___
//  | |  | |/ _ \| __|  _| | |/ _ \/ __|
//  | |__| | (_) | |_| | | | |  __/\__ \
//  |_____/ \___/ \__|_| |_|_|\___||___/
// https://github.com/risingstarfish/dotfiles
// version 0.1.0
//
// Licensed under the MIT License <http://opensource.org/licenses/MIT>.
// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Pierce Katai
// <169690632+risingstarfish@users.noreply.github.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#pragma once

#include <algorithm>
#include <iterator>
#include <meta>
#include <optional>
#include <print>
#include <span>
#include <string>
#include <string_view>
#include <utility>


// todo: detect ^C, ^D, etc.
namespace risingstarfish::cli {
struct flags {
    bool use_short;
    bool use_long;
};

struct metadata {
    std::string_view name;     // app name
    std::string_view version;  // app version
    std::string_view about;    // short description
    std::string_view author;   // name/email
};

template<typename T, flags F>
// requires movable T
struct option {
    std::optional<T> initialiser {};         // default value
    std::string_view description;            // description of variable
    bool (*validator)(const T &) = nullptr;  // function to validate variable against
    std::string_view cli_name;               // Optional custom CLI name (overrides auto-transform)

    option() = default;
    /* explicit */ option(T t) : initialiser(std::move(t)) {}

    option(T t, std::string_view desc, bool (*val)(const T &) = nullptr) :
      initialiser(std::move(t)), description(desc), validator(val) {}

    option(T t, std::string_view desc, std::string_view name, bool (*val)(const T &) = nullptr) :
      initialiser(std::move(t)), description(desc), validator(val), cli_name(name) {}

    // no default required
    option(std::nullopt_t, std::string_view desc, bool (*val)(const T &) = nullptr) :
      description(desc), validator(val) {}

    option(std::nullopt_t, std::string_view desc, std::string_view name, bool (*val)(const T &) = nullptr) :
      description(desc), cli_name(name), validator(val) {}

    // flags
    static constexpr bool use_short = F.use_short;
    static constexpr bool use_long  = F.use_long;

    static_assert(use_short || use_long, "Either use_short or use_long must be true");
};

consteval auto spec_to_opts(std::meta::info opts, std::meta::info spec) noexcept -> std::meta::info {
    std::vector<std::meta::info> new_members;
    for (auto member : nonstatic_data_members_of(spec, std::meta::access_context::current())) {
        const auto                     new_type = template_arguments_of(type_of(member))[0];
        std::meta::data_member_options member_opts {};
        member_opts.name = std::meta::identifier_of(member);

        new_members.push_back(data_member_spec(new_type, member_opts));
    }
    return define_aggregate(opts, new_members);
}

[[nodiscard]] consteval auto get_member_by_name(std::meta::info           type,
                                                std::string_view          name,
                                                std::meta::access_context ctx) noexcept -> std::meta::info {
    for (auto m : nonstatic_data_members_of(type, ctx)) {
        if (identifier_of(m) == name) {
            return m;
        }
    }
    std::unreachable();
}

// FIXME: called 3 times. cache during first loop
// Helper to convert C++ identifier (underscore) to CLI name (hyphen)
[[nodiscard]] inline auto to_cli_name(std::string_view name) noexcept -> std::string {
    if (name.empty()) [[unlikely]] {
        return {};
    }
    std::string res;
    res.resize(name.size());
    for (std::size_t i = 0; i < name.size(); ++i) {
        res[i] = (name[i] == '_') ? '-' : name[i];
    }

    return res;
}


using std::string_view_literals::operator""sv;

struct clap {
    // todo: remove / redo
    static constexpr auto version_long = "--version"sv;
    static constexpr auto help_short   = "-h"sv;
    static constexpr auto help_long    = "--help"sv;

    template<typename Spec>
    inline void version(this const Spec &) {
        constexpr auto app_name = Spec::metadata_.name;
        constexpr auto version  = Spec::metadata_.version;

        std::println(stdout, "{} version {}", app_name, version);
    }

    template<typename Spec>
    inline void help(this const Spec &spec) {
        constexpr auto app_name = Spec::metadata_.name;
        constexpr auto version  = Spec::metadata_.version;
        constexpr auto about    = Spec::metadata_.about;
        constexpr auto author   = Spec::metadata_.author;


        std::string usage_str;
        usage_str.reserve(500);  // TODO: adjust

        std::format_to(std::back_inserter(usage_str), "{}\n  by: {}\n", about, author);
#if defined(_WIN32) || defined(__CYGWIN__) || defined(__MINGW32__)
        std::format_to(std::back_inserter(usage_str), "\nUsage:\n  {}.exe [options]\n", app_name);
#else
        std::format_to(std::back_inserter(usage_str), "\nUsage:\n  {} [options]\n", app_name);
#endif  // (_WIN32) || (__CYGWIN__)  || (__MINGW32__)

        // TODO: print examples with required and optional args

        constexpr auto ctx          = std::meta::access_context::current();
        auto           max_long_len = version_long.size();
        template for (constexpr auto sm : define_static_array(nonstatic_data_members_of(^^Spec, ctx))) {
            auto &cur = spec.[:sm:];
            if constexpr (cur.use_long) {
                // Use CLI name for display length calculation
                auto name    = cur.cli_name.empty() ? to_cli_name(identifier_of(sm)) : std::string(cur.cli_name);
                max_long_len = std::max(max_long_len, 2 + name.size());  // "--" + name
            }
        }

        // Print options
        constexpr auto min_gap        = 4UZ;  // between long and description
        constexpr auto max_short_size = 4UZ;  // max 4 "-X, "

        usage_str += "\nOPTIONS:\n";
        template for (constexpr auto sm : define_static_array(nonstatic_data_members_of(^^Spec, ctx))) {
            auto &cur = spec.[:sm:];

            std::string short_str;
            std::string long_str;

            // Determine the name to display (CLI name)
            auto name = cur.cli_name.empty() ? to_cli_name(identifier_of(sm)) : std::string {cur.cli_name};

            if constexpr (cur.use_short) {
                short_str = std::format("-{}", name[0]);
                if constexpr (cur.use_long) {
                    short_str += ", ";
                }
            }

            if constexpr (cur.use_long) {
                long_str = std::format("--{}", name);
            }

            // TODO: max 50 characters wide description,
            // TODO: then newline but dont split words
            if (cur.initialiser.has_value()) {
                std::format_to(std::back_inserter(usage_str),
                               "  {:<{}}{:<{}}{} (default: {})\n",
                               short_str,
                               max_short_size,
                               long_str,
                               max_long_len + min_gap,
                               cur.description,
                               cur.initialiser.value());
            } else {
                std::format_to(std::back_inserter(usage_str),
                               "  {:<{}}{:<{}}{}\n",
                               short_str,
                               max_short_size,
                               long_str,
                               max_long_len + min_gap,
                               cur.description);
            }
        }
        // help
        const auto long_width = max_long_len + max_short_size;
        std::format_to(
          std::back_inserter(usage_str), "  {}, {:<{}}{}\n", help_short, help_long, long_width, "Print help and exit");
        // version
        std::format_to(
          std::back_inserter(usage_str), "      {:<{}}{} ({})\n", version_long, long_width, "Show version", version);

        std::println(stderr, "{}", usage_str);
    }

    //===============================================================================================================
    // for enums, have to make ">>" overload and formatter
    //===============================================================================================================
    template<typename Spec>
    auto parse(this const Spec &spec, int argc, const char **argv) {
        std::vector<std::string_view> cmdline(argv + 1, argv + argc);

        // fixme: search in order of appearance
        // search for help
        if (std::find_if(cmdline.begin(),
                         cmdline.end(),
                         [](std::string_view arg) {
                             return arg == help_short || arg == help_long;
                         })
            != cmdline.end()) {

            spec.help();
            std::exit(EXIT_SUCCESS);
        }

        // search for version
        if (std::find_if(cmdline.begin(),
                         cmdline.end(),
                         [](std::string_view arg) {
                             return arg == version_long;
                         })
            != cmdline.end()) {

            spec.version();
            std::exit(EXIT_SUCCESS);
        }


        struct Opts;
        consteval {
            spec_to_opts(^^Opts, ^^Spec);
        }
        Opts opts;

        constexpr auto ctx = std::meta::access_context::current();
        template for (constexpr auto sm : define_static_array(nonstatic_data_members_of(^^Spec, ctx))) {
            constexpr auto om = get_member_by_name(^^Opts, identifier_of(sm), ctx);

            auto          &cur  = spec.[:sm:];
            constexpr auto type = type_of(om);

            // Determine the CLI name to match against (either custom or auto-transformed)
            std::string cli_name = cur.cli_name.empty() ? to_cli_name(identifier_of(sm)) : std::string {cur.cli_name};

            // find the argument associated with this option
            auto it = std::find_if(cmdline.begin(), cmdline.end(), [&](std::string_view arg) {
                // Check short
                if (cur.use_short && arg.size() == 2 && arg[0] == '-' && arg[1] == cli_name[0]) {
                    return true;
                }
                // Check long
                if (cur.use_long && arg.starts_with("--") && arg.substr(2) == cli_name) {
                    return true;
                }
                return false;
            });

            // Check if this is a bool flag - no value required
            if constexpr (type == ^^bool) {
                opts.[:om:] = true;  // Mark as present
            } else {
                // no such argument
                if (it == cmdline.end()) {
                    if constexpr (has_template_arguments(type) && template_of(type) == ^^std::optional) {
                        // the type is optional, so the argument is too
                        continue;
                    } else if (cur.initialiser) {
                        // the type isn't optional, but an initialiser is provided, use that
                        opts.[:om:] = *cur.initialiser;
                    } else {
                        std::println(stderr, "Missing required parameter <{}>", cli_name);
                        spec.help();
                        std::exit(EXIT_FAILURE);
                    }
                } else {
                    // It's a standard key-value option
                    if (it + 1 == cmdline.end()) {
                        std::println(stderr, "option '{}' for '{}' is missing a value", *it, cli_name);
                        spec.help();
                        std::exit(EXIT_FAILURE);
                    }

                    // alright, found our argument, try to parse it
                    std::stringstream iss;
                    iss << it[1];

                    if (iss >> opts.[:om:]; !iss) {
                        std::println(stderr, "Failed to parse '{}' into option '{}'\n", it[1], cli_name);
                        spec.help();  // todo: remove and print valid options
                        std::exit(EXIT_FAILURE);
                    }
                }
            }

            if (cur.validator && !cur.validator(opts.[:om:])) {
                std::println(stderr, "Validation failed for option '{}'. Invalid value '{}'", cli_name, opts.[:om:]);
                spec.help();
                std::exit(EXIT_FAILURE);
            }
        }

        return opts;
    }
};
}  // namespace risingstarfish::cli
