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

#ifndef DOTFILES_USE_STD_MODULES
#    include <chrono>
#    include <cstddef>  // size_t
#    include <filesystem>
#    include <format>
#    include <functional>
#    include <print>
#    include <source_location>  // current
#    include <string>
#    include <string_view>
#    include <type_traits>
#    include <utility>  // forward, move
#else
import std;
#endif                  // DOTFILES_USE_STD_MODULES

namespace dotfiles {

template<typename T>
inline void do_not_optimise_away(const T &value) {
#if defined(__clang__) || defined(__GNUC__)
    asm volatile("" : : "r,m"(value) : "memory");
#endif
}

template<class Func>
inline void invoke_and_prevent_optimization(Func &&func) {
    if constexpr (std::is_void_v<std::invoke_result_t<Func>>) {
        std::invoke(std::forward<Func>(func));
        // Prevent compiler from reordering timer calls around this function
#if defined(__clang__) || defined(__GNUC__)
        __asm__ __volatile__("" : : : "memory");
#endif
    } else {
        auto result = std::invoke(std::forward<Func>(func));
        // Force the compiler to compute the result and prevent reordering
#if defined(__clang__) || defined(__GNUC__)
        __asm__ __volatile__("" : : "r,m"(result) : "memory");
#endif
    }
}

struct default_logger {
    template<typename... Args>
    void operator()(std::format_string<Args...> fmt, Args &&...args) const {
        std::print(fmt, std::forward<Args>(args)...);
    }
};

struct null_logger {
    template<typename... Args>
    void operator()(std::format_string<Args...>, Args &&...) const {}
};

template<class Logger   = default_logger,
         class Duration = std::chrono::milliseconds,
         class Clock    = std::chrono::high_resolution_clock>
class timer {
public:
    static_assert(std::is_move_constructible_v<Logger>, "Logger type must be move constructible");

    using TimePoint      = Clock::time_point;
    using NativeDuration = Clock::duration;

    explicit timer(std::string_view     label             = "Unnamed Timer",
                   bool                 start_immediately = true,
                   Logger               logger            = Logger {},
                   std::source_location location          = std::source_location::current()) :
      m_label(label), m_location(location), m_logger(std::move(logger)) {
        if (start_immediately) {
            m_start  = Clock::now();
            m_active = true;
        }
    }

    timer(timer &&other) noexcept :
      m_label(std::move(other.m_label)),
      m_location(other.m_location),
      m_start(other.m_start),
      m_accumulated(other.m_accumulated),
      m_active(other.m_active),
      m_finished(other.m_finished),
      m_logger(std::move(other.m_logger)) {
        other.m_active   = false;
        other.m_finished = true;
    }

    timer &operator=(timer &&other) noexcept {
        if (this != &other) {
            if (m_active) {
                stop();
            }
            m_label          = std::move(other.m_label);
            m_location       = other.m_location;
            m_start          = other.m_start;
            m_active         = other.m_active;
            m_finished       = other.m_finished;
            m_accumulated    = other.m_accumulated;
            m_logger         = std::move(other.m_logger);
            other.m_active   = false;
            other.m_finished = true;
        }
        return *this;
    }

    timer(const timer &)            = delete;
    timer &operator=(const timer &) = delete;

    ~timer() { stop(); }

    void restart() {
        print();  // TODO: edit output to indicate restart
        m_start       = Clock::now();
        m_accumulated = Clock::duration::zero();
        m_active      = true;
        m_finished    = false;
    }

    void reset() noexcept {
        m_start       = Clock::now();
        m_accumulated = Clock::duration::zero();
        m_finished    = false;
    }

    void stop() {
        if (m_finished) {
            return;
        }
        if (m_active) {
            pause();
        }
        print();
        m_finished = true;
    }

    void pause() noexcept {
        if (!m_active) {
            return;
        }
        const auto now  = Clock::now();
        m_accumulated  += (now - m_start);
        m_active        = false;
    }

    void resume() noexcept {
        if (m_active || m_finished) {
            return;
        }
        m_start  = Clock::now();
        m_active = true;
    }

    void print() const {
        m_logger("[TIMER] {} -> {}: {} (at {}:{})\n",
                 m_location.function_name(),
                 m_label,
                 elapsed(),
                 std::filesystem::path(m_location.file_name()).filename(),
                 m_location.line());
    }

    void lap(std::string_view note = "") const {
        m_logger("[TIMER LAP] {} -> {}: {} | Note: {}\n", m_location.function_name(), m_label, elapsed(), note);
    }

    [[nodiscard]] Duration elapsed() const noexcept {
        auto total = m_accumulated;
        if (m_active) {
            total += (Clock::now() - m_start);
        }
        return std::chrono::duration_cast<Duration>(total);
    }

    [[nodiscard]] bool is_running() const { return m_active; }

    [[nodiscard]] auto count() const -> std::size_t { return elapsed().count(); }

private:
    std::string          m_label;
    std::source_location m_location;
    TimePoint            m_start       = Clock::now();
    bool                 m_active      = false;
    bool                 m_finished    = false;  // track output
    NativeDuration       m_accumulated = Clock::duration::zero();
    Logger               m_logger;
};

}  // namespace dotfiles
