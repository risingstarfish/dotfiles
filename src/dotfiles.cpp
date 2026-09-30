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
// Copyright (c) 2026 Pierce Katai <169690632+risingstarfish@users.noreply.github.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


#include "dotfiles/banners.hpp"
#include "dotfiles/timer.hpp"
#include "dotfiles/utility/cli.hpp"
#include "dotfiles/utility/fixed_string.hpp"


using namespace risingstarfish::cli;
using namespace dotfiles;


struct args : clap {
    static constexpr metadata metadata_ {
      .name    = "dotfiles",
      .version = "0.1.0",
      .about   = "Dotfiles installer for Mac, Linux, Windows, and WSL.",
      .author  = "Pierce Katai",
    };

    option<bool, flags {.use_short = true, .use_long = true}> update {false, "Update from Git before installing."};
};

int main(int argc, const char **argv) {
    timer                 timer {"main"};
    [[maybe_unused]] auto opts = args {}.parse(argc, argv);

    utility::print_start();

    utility::print_end(shell::zsh);
}
