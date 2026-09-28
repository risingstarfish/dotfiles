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
// Copyright (c) 2026 Pierce Katai
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

#include "common.hpp"
#include "colours.hpp"

#ifndef DOTFILES_USE_STD_MODULES
#    include <format>
#    include <meta>
#    include <print>
#    include <string>
#    include <string_view>
#    include <type_traits>
#else
import std;
#endif  // DOTFILES_USE_STD_MODULES

namespace dotfiles::utility {



void print_start(){

}


void print_end(shell sh, bool autorestart = false) {
    // 45 inner width
    constexpr std::string_view banner_top    = "╭─────────────────────────────────────────╮\n";
    constexpr std::string_view banner_blank  = "│                                         │\n";
    constexpr std::string_view banner_title  = "│         Installation Complete!          │\n";
    constexpr std::string_view banner_bottom = "╰─────────────────────────────────────────╯\n";

    std::string msg;
    if (autorestart) {
        msg = "│           Restarting shell...           │\n";
    } else {
        msg = "│          Returning to shell...          │\n";
        switch (sh) {
            using enum shell;
            case zsh: {
                msg += "│  Run `exec zsh` to apply your changes.  │\n";
                break;
            }
            case pwsh: msg += "│ Run `. $PROFILE` to apply your changes. │\n"; break;
        }
    }

    std::println("{}{}{}{}{}{}{}",
                 banner_top,
                 banner_blank,
                 banner_title,
                 banner_blank,
                 msg,
                 banner_blank,
                 banner_bottom);
}

}  // namespace dotfiles::utility
