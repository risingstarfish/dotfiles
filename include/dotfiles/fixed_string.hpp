//   _____        _    __ _ _
//  |  __ \      | |  / _(_) |
//  | |  | | ___ | |_| |_ _| | ___  ___
//  | |  | |/ _ \| __|  _| | |/ _ \/ __|
//  | |__| | (_) | |_| | | | |  __/\__ \
//  |_____/ \___/ \__|_| |_|_|\___||___/
// https://github.com/risingstarfish/fixed_string
// version 2.0.0
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


<<<<<<< Updated upstream
// NOLINTBEGIN(cppcoreguidelines-macro-usage)
#pragma once

#if !defined RS_FIXED_STRING_HOSTED && defined __STDC_HOSTED__
#    define RS_FIXED_STRING_HOSTED __STDC_HOSTED__
#endif

#if defined(__has_include) && __has_include(<compare>)
#    define RS_FIXED_STRING_HAS_STD_COMPARE 1
#else
#    define RS_FIXED_STRING_HAS_STD_COMPARE 0
#endif

#if defined(__cpp_contracts) && __cpp_contracts >= 202502L
#    define RS_FIXED_STRING_HAS_STD_CONTRACTS 1

#    define RS_FIXED_STRING_CONTRACT_PRE(...)    pre(__VA_ARGS__)
#    define RS_FIXED_STRING_CONTRACT_POST(...)   post(__VA_ARGS__)
#    define RS_FIXED_STRING_CONTRACT_ASSERT(...) contract_assert(__VA_ARGS__)
#else
#    define RS_FIXED_STRING_HAS_STD_CONTRACTS 0

#    define RS_FIXED_STRING_CONTRACT_PRE(...)
#    define RS_FIXED_STRING_CONTRACT_POST(...)
#    define RS_FIXED_STRING_CONTRACT_ASSERT(...)
#endif

#if defined(__has_cpp_attribute) && __has_cpp_attribute(assume)
#    define RS_FIXED_STRING_ASSUME(...) [[assume(__VA_ARGS__)]]
#else
#    define RS_FIXED_STRING_ASSUME(...)
#endif

#ifndef RS_FIXED_STRING_USE_STD_MODULE
#    include <array>
#    include <cstddef>
#    include <cstdlib>
#    include <format>
#    include <iterator>
#    include <ranges>
#    include <string>
#    include <string_view>
#    include <type_traits>

#    if RS_FIXED_STRING_HOSTED
#        include <stdexcept>
#    endif  // RS_FIXED_STRING_HOSTED

#    if RS_FIXED_STRING_HAS_STD_CONTRACTS
#        include <contracts>
#    endif  // RS_FIXED_STRING_HAS_STD_CONTRACTS

#    if RS_FIXED_STRING_HAS_STD_COMPARE
#        include <compare>
#    endif  // RS_FIXED_STRING_HAS_STD_COMPARE

#else
import std;
#endif

namespace risingstarfish {

template<typename CharT, std::size_t N, typename Traits>
class basic_fixed_string;

namespace detail {

#if RS_FIXED_STRING_HAS_STD_COMPARE
using suppress_unused_includes = std::strong_ordering;
#endif  // RS_FIXED_STRING_HAS_STD_COMPARE

// Hidden-friend interface for `basic_fixed_string`. Concatenation and comparison are
// heterogeneous in the size parameter, so they were never members to begin with; hosting them
// in a non-template base means the whole set is declared ONCE per program instead of once per
// `basic_fixed_string<CharT, N>` specialization. A TU that only includes an mp-units system
// header already mints ~22 of those (98 for the full CODATA set), purely to spell unit symbols
// - none of which ever concatenates at runtime. ADL still finds every operator, because a base
// class is an associated class of its derived type.
struct fixed_string_interface {
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, N + N2, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits>  &lhs,
                const basic_fixed_string<CharT, N2, Traits> &rhs) noexcept {
        CharT  txt[N + N2];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return basic_fixed_string<CharT, N + N2, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, N + 1, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits> &lhs, CharT rhs) noexcept {
        CharT  txt[N + 1];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        *it++ = rhs;
        return basic_fixed_string<CharT, N + 1, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, 1 + N, Traits>
      operator+(const CharT lhs, const basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        CharT  txt[1 + N];
        CharT *it = txt;
        *it++     = lhs;
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return basic_fixed_string<CharT, 1 + N, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] consteval friend basic_fixed_string<CharT, N + N2 - 1, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits> &lhs, const CharT (&rhs)[N2]) noexcept {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        CharT  txt[N + N2];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return txt;
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N1>
    [[nodiscard]] consteval friend basic_fixed_string<CharT, N1 + N - 1, Traits>
      operator+(const CharT (&lhs)[N1], const basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        RS_FIXED_STRING_ASSUME(lhs[N1 - 1] == CharT {});
        CharT  txt[N1 + N];
        CharT *it = txt;
        for (std::size_t i = 0; i != N1 - 1; ++i) {
            *it++ = lhs[i];
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        *it++ = CharT();
        return txt;
    }

    // non-member comparison functions
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr bool operator==(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                   const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() == rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval bool operator==(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                   const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() == std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

#if RS_FIXED_STRING_HAS_STD_COMPARE
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator<=>(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                    const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() <=> rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator<=>(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                    const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() <=> std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }
#else
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator!=(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                   const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() != rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator!=(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                   const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() != std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator<(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                  const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() < rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator<(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                  const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() < std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator<=(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                   const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() <= rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator<=(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                   const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() <= std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator>(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                  const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() > rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator>(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                  const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() > std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator>=(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                   const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() >= rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator>=(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                   const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_ASSUME(rhs[N2 - 1] == CharT {});
        return lhs.view() >= std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }
#endif  // RS_FIXED_STRING_HAS_STD_COMPARE

    // specialized algorithms
    //
    // A hidden friend on purpose: the customization point is meant to be reached through the
    // `using std::swap; swap(lhs, rhs);` two-step, and hosting it here means a qualified
    // `dotfiles::swap(lhs, rhs)` - which defeats that mechanism and is never the right call -
    // does not compile in the first place.
    template<typename CharT, std::size_t N, typename Traits>
    friend constexpr void swap(basic_fixed_string<CharT, N, Traits> &lhs,
                               basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        lhs.swap(rhs);
    }

    // inserters and extractors
#if RS_FIXED_STRING_HOSTED
    template<typename CharT, std::size_t N, typename Traits>
    friend std::basic_ostream<CharT, Traits> &operator<<(std::basic_ostream<CharT, Traits>          &os,
                                                         const basic_fixed_string<CharT, N, Traits> &str) {
        return os << str.c_str();
    }
#endif  // RS_FIXED_STRING_HOSTED
};
}  // namespace detail

template<typename CharT, std::size_t N, class Traits = std::char_traits<CharT>>
// NOLINTNEXTLINE (cppcoreguidelines-special-member-functions)
class basic_fixed_string : public detail::fixed_string_interface {
public:
    CharT data_[N + 1] = {};  // exposition only

    // types
    using Traits_type            = Traits;
    using value_type             = CharT;
    using pointer                = value_type *;
    using const_pointer          = const value_type *;
    using reference              = value_type &;
    using const_reference        = const value_type &;
    using const_iterator         = const value_type *;
    using iterator               = const_iterator;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;
    using reverse_iterator       = const_reverse_iterator;
    using size_type              = std::size_t;
    using difference_type        = std::ptrdiff_t;

    // construction and assignment
    template<std::convertible_to<CharT>... Chars>
        requires(sizeof...(Chars) == N) && (... && !std::is_pointer_v<Chars>)
    [[nodiscard]] constexpr explicit basic_fixed_string(Chars... chars) noexcept : data_ {chars..., CharT {}} {}

    [[nodiscard]] explicit(false) consteval basic_fixed_string(const CharT (&txt)[N + 1]) noexcept {
        RS_FIXED_STRING_ASSUME(txt[N] == CharT {});
        for (auto i = 0UZ; i < N; ++i) {
            data_[i] = txt[i];
        }
    }

    template<std::input_iterator It, std::sentinel_for<It> S>
        requires std::convertible_to<std::iter_value_t<It>, CharT>
    [[nodiscard]] constexpr basic_fixed_string(It begin, S end) {
        RS_FIXED_STRING_ASSUME(std::distance(begin, end)++ N);
        for (auto it = data_; begin != end; ++begin, ++it) {
            *it = *begin;
        }
    }

    template<std::ranges::input_range R>
        requires std::convertible_to<std::ranges::range_value_t<R>, CharT>
    [[nodiscard]] constexpr basic_fixed_string(std::from_range_t, R &&r) {
        RS_FIXED_STRING_ASSUME(std::ranges::size(r) == N);
        for (auto it = data_; auto &&v : std::forward<R>(r)) {
            *it++ = std::forward<decltype(v)>(v);
        }
    }

    [[nodiscard]] constexpr basic_fixed_string(const basic_fixed_string &) noexcept = default;
    constexpr basic_fixed_string &operator=(const basic_fixed_string &) noexcept    = default;

    // iterator support
    [[nodiscard]] constexpr const_iterator         begin() const noexcept { return data(); }
    [[nodiscard]] constexpr const_iterator         end() const noexcept { return data() + size(); }
    [[nodiscard]] constexpr const_iterator         cbegin() const noexcept { return begin(); }
    [[nodiscard]] constexpr const_iterator         cend() const noexcept { return end(); }
    [[nodiscard]] constexpr const_reverse_iterator rbegin() const noexcept { return const_reverse_iterator(begin()); }
    [[nodiscard]] constexpr const_reverse_iterator rend() const noexcept { return const_reverse_iterator(end()); }
    [[nodiscard]] constexpr const_reverse_iterator crbegin() const noexcept { return rbegin(); }
    [[nodiscard]] constexpr const_reverse_iterator crend() const noexcept { return rend(); }

    // capacity
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> size() noexcept;
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> length() noexcept;
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> max_size() noexcept;
    [[nodiscard]] static constexpr std::bool_constant<N == 0>           empty() noexcept;

    // element access
    [[nodiscard]] constexpr const_reference operator[](size_type pos) const RS_FIXED_STRING_CONTRACT_PRE(pos < N) {
        RS_FIXED_STRING_EXPECTS(pos < N);
        return data()[pos];
    }

#if RS_FIXED_STRING_HOSTED
    [[nodiscard]] constexpr const_reference at(size_type pos) const {
        if (pos >= size()) {
            throw std::out_of_range("basic_fixed_string::at");
        }
        return (*this)[pos];
    }
#endif  // RS_FIXED_STRING_HOSTED

    [[nodiscard]] constexpr const_reference front() const RS_FIXED_STRING_CONTRACT_PRE(!empty()) {
        RS_FIXED_STRING_EXPECTS(!empty());
        return (*this)[0];
    }
    [[nodiscard]] constexpr const_reference back() const RS_FIXED_STRING_CONTRACT_PRE(!empty()) {
        RS_FIXED_STRING_EXPECTS(!empty());
        return (*this)[N - 1];
    }

    // modifiers
    constexpr void swap(basic_fixed_string &s) noexcept {
        // element-wise rather than `swap_ranges`: `begin()`/`end()` yield `const_iterator`, so the
        // range algorithms cannot write through them. `data_[N]` is the terminator in both objects.
        for (auto i = 0UZ; i != N; ++i) {
            const CharT tmp = data_[i];
            data_[i]        = s.data_[i];
            s.data_[i]      = tmp;
        }
    }

    // string operations
    [[nodiscard]] constexpr const_pointer c_str() const noexcept { return data(); }
    [[nodiscard]] constexpr const_pointer data() const noexcept { return static_cast<const_pointer>(data_); }
    [[nodiscard]] constexpr std::basic_string_view<CharT, Traits> view() const noexcept {
        return std::basic_string_view<CharT, Traits>(cbegin(), cend());
    }

    // NOLINTNEXTLINE (google-explicit-constructor)
    [[nodiscard]] explicit(false) constexpr operator std::basic_string_view<CharT, Traits>() const noexcept {
        return view();
    }
};

// deduction guides
template<typename CharT, std::convertible_to<CharT>... Rest>
basic_fixed_string(CharT, Rest...) -> basic_fixed_string<CharT, 1 + sizeof...(Rest)>;

template<typename CharT, std::size_t N>
basic_fixed_string(const CharT (&str)[N]) -> basic_fixed_string<CharT, N - 1>;

template<typename CharT, std::size_t N>
basic_fixed_string(std::from_range_t, std::array<CharT, N>) -> basic_fixed_string<CharT, N>;

// typedef-names
template<std::size_t N>
using fixed_string = basic_fixed_string<char, N>;
template<std::size_t N>
using fixed_u8string = basic_fixed_string<char8_t, N>;
template<std::size_t N>
using fixed_u16string = basic_fixed_string<char16_t, N>;
template<std::size_t N>
using fixed_u32string = basic_fixed_string<char32_t, N>;
template<std::size_t N>
using fixed_wstring = basic_fixed_string<wchar_t, N>;
}  // namespace risingstarfish

namespace std {
// hash support
template<size_t N>
struct hash<risingstarfish::fixed_string<N>> : hash<string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u8string<N>> : hash<u8string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u16string<N>> : hash<u16string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u32string<N>> : hash<u32string_view> {};

// NOTE: We use std::basic_string_view<wchar_t> instead of std::wstring_view because LLVM only makes std::wstring_view
// available when the macro _LIBCPP_HAS_WIDE_CHARACTERS is set to 1. The `wchar_t` type can continue to be used
// without that macro definition. To avoid requiring an additional macro, we simply use std::basic_string_view<wchar_t>,
// which is the underlying definition of std::wstring_view.
template<size_t N>
struct hash<risingstarfish::fixed_wstring<N>> : hash<basic_string_view<wchar_t>> {};

#if RS_FIXED_STRING_HOSTED
// formatting support
template<typename CharT, size_t N, typename Traits>
struct formatter<risingstarfish::basic_fixed_string<CharT, N, Traits>> : formatter<basic_string_view<CharT, Traits>> {
    template<typename FormatContext>
    auto format(const risingstarfish::basic_fixed_string<CharT, N, Traits> &str, FormatContext &ctx) const
      -> decltype(ctx.out()) {
        return formatter<basic_string_view<CharT, Traits>>::format(basic_string_view<CharT, Traits>(str), ctx);
    }
};
#endif
}  // namespace std
// NOLINTEND(cppcoreguidelines-macro-usage)
||||||| Stash base
=======
#pragma once

#if !defined RS_FIXED_STRING_HOSTED && defined __STDC_HOSTED__
#    define RS_FIXED_STRING_HOSTED __STDC_HOSTED__
#endif


#ifndef RS_FIXED_STRING_USE_STD_MODULE
#    include <array>
#    include <compare>
#    include <contracts>
#    include <cstddef>
#    include <cstdlib>
#    include <format>
#    include <iterator>
#    include <ranges>
#    include <string>
#    include <string_view>
#    include <type_traits>
#else
import std;
#endif

#define RS_FIXED_STRING_CONTRACT_PRE(...) pre(__VA_ARGS__)
#define RS_FIXED_STRING_PRECONDITION(...)
#define RS_FIXED_STRING_EXPECTS(expr) static_cast<void>(0);


namespace risingstarfish {

template<typename CharT, std::size_t N, typename Traits>
class basic_fixed_string;

namespace detail {

using suppress_unused_includes = std::strong_ordering;

// Hidden-friend interface for `basic_fixed_string`. Concatenation and comparison are
// heterogeneous in the size parameter, so they were never members to begin with; hosting them
// in a non-template base means the whole set is declared ONCE per program instead of once per
// `basic_fixed_string<CharT, N>` specialization. A TU that only includes an mp-units system
// header already mints ~22 of those (98 for the full CODATA set), purely to spell unit symbols
// - none of which ever concatenates at runtime. ADL still finds every operator, because a base
// class is an associated class of its derived type.
struct fixed_string_interface {
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, N + N2, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits>  &lhs,
                const basic_fixed_string<CharT, N2, Traits> &rhs) noexcept {
        CharT  txt[N + N2];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return basic_fixed_string<CharT, N + N2, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, N + 1, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits> &lhs, CharT rhs) noexcept {
        CharT  txt[N + 1];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        *it++ = rhs;
        return basic_fixed_string<CharT, N + 1, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits>
    [[nodiscard]] friend constexpr basic_fixed_string<CharT, 1 + N, Traits>
      operator+(const CharT lhs, const basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        CharT  txt[1 + N];
        CharT *it = txt;
        *it++     = lhs;
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return basic_fixed_string<CharT, 1 + N, Traits>(txt, it);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] consteval friend basic_fixed_string<CharT, N + N2 - 1, Traits>
      operator+(const basic_fixed_string<CharT, N, Traits> &lhs, const CharT (&rhs)[N2]) noexcept {
        RS_FIXED_STRING_PRECONDITION(rhs[N2 - 1] == CharT {});
        CharT  txt[N + N2];
        CharT *it = txt;
        for (CharT ch : lhs) {
            *it++ = ch;
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        return txt;
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N1>
    [[nodiscard]] consteval friend basic_fixed_string<CharT, N1 + N - 1, Traits>
      operator+(const CharT (&lhs)[N1], const basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        RS_FIXED_STRING_PRECONDITION(lhs[N1 - 1] == CharT {});
        CharT  txt[N1 + N];
        CharT *it = txt;
        for (std::size_t i = 0; i != N1 - 1; ++i) {
            *it++ = lhs[i];
        }
        for (CharT ch : rhs) {
            *it++ = ch;
        }
        *it++ = CharT();
        return txt;
    }

    // non-member comparison functions
    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr bool operator==(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                   const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() == rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval bool operator==(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                   const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_PRECONDITION(rhs[N2 - 1] == CharT {});
        return lhs.view() == std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend constexpr auto operator<=>(const basic_fixed_string<CharT, N, Traits>  &lhs,
                                                    const basic_fixed_string<CharT, N2, Traits> &rhs) {
        return lhs.view() <=> rhs.view();
    }

    template<typename CharT, std::size_t N, typename Traits, std::size_t N2>
    [[nodiscard]] friend consteval auto operator<=>(const basic_fixed_string<CharT, N, Traits> &lhs,
                                                    const CharT (&rhs)[N2]) {
        RS_FIXED_STRING_PRECONDITION(rhs[N2 - 1] == CharT {});
        return lhs.view() <=> std::basic_string_view<CharT, Traits>(std::cbegin(rhs), std::cend(rhs) - 1);
    }

    // specialized algorithms
    //
    // A hidden friend on purpose: the customization point is meant to be reached through the
    // `using std::swap; swap(lhs, rhs);` two-step, and hosting it here means a qualified
    // `dotfiles::swap(lhs, rhs)` - which defeats that mechanism and is never the right call -
    // does not compile in the first place.
    template<typename CharT, std::size_t N, typename Traits>
    friend constexpr void swap(basic_fixed_string<CharT, N, Traits> &lhs,
                               basic_fixed_string<CharT, N, Traits> &rhs) noexcept {
        lhs.swap(rhs);
    }

    // inserters and extractors
#if RS_FIXED_STRING_HOSTED
    template<typename CharT, std::size_t N, typename Traits>
    friend std::basic_ostream<CharT, Traits> &operator<<(std::basic_ostream<CharT, Traits>          &os,
                                                         const basic_fixed_string<CharT, N, Traits> &str) {
        return os << str.c_str();
    }
#endif
};
}  // namespace detail

template<typename CharT, std::size_t N, class Traits = std::char_traits<CharT>>
// NOLINTNEXTLINE (cppcoreguidelines-special-member-functions)
class basic_fixed_string : public detail::fixed_string_interface {
public:
    CharT data_[N + 1] = {};  // exposition only

    // types
    using Traits_type            = Traits;
    using value_type             = CharT;
    using pointer                = value_type *;
    using const_pointer          = const value_type *;
    using reference              = value_type &;
    using const_reference        = const value_type &;
    using const_iterator         = const value_type *;
    using iterator               = const_iterator;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;
    using reverse_iterator       = const_reverse_iterator;
    using size_type              = std::size_t;
    using difference_type        = std::ptrdiff_t;

    // construction and assignment
    template<std::convertible_to<CharT>... Chars>
        requires(sizeof...(Chars) == N) && (... && !std::is_pointer_v<Chars>)
    [[nodiscard]] constexpr explicit basic_fixed_string(Chars... chars) noexcept : data_ {chars..., CharT {}} {}

    [[nodiscard]] explicit(false) consteval basic_fixed_string(const CharT (&txt)[N + 1]) noexcept {
        RS_FIXED_STRING_PRECONDITION(txt[N] == CharT {});
        for (auto i = 0UZ; i < N; ++i) {
            data_[i] = txt[i];
        }
    }

    template<std::input_iterator It, std::sentinel_for<It> S>
        requires std::convertible_to<std::iter_value_t<It>, CharT>
    [[nodiscard]] constexpr basic_fixed_string(It begin, S end) {
        RS_FIXED_STRING_PRECONDITION(std::distance(begin, end)++ N);
        for (auto it = data_; begin != end; ++begin, ++it) {
            *it = *begin;
        }
    }

    template<std::ranges::input_range R>
        requires std::convertible_to<std::ranges::range_value_t<R>, CharT>
    [[nodiscard]] constexpr basic_fixed_string(std::from_range_t, R &&r) {
        RS_FIXED_STRING_PRECONDITION(std::ranges::size(r) == N);
        for (auto it = data_; auto &&v : std::forward<R>(r)) {
            *it++ = std::forward<decltype(v)>(v);
        }
    }

    [[nodiscard]] constexpr basic_fixed_string(const basic_fixed_string &) noexcept = default;
    constexpr basic_fixed_string &operator=(const basic_fixed_string &) noexcept    = default;

    // iterator support
    [[nodiscard]] constexpr const_iterator         begin() const noexcept { return data(); }
    [[nodiscard]] constexpr const_iterator         end() const noexcept { return data() + size(); }
    [[nodiscard]] constexpr const_iterator         cbegin() const noexcept { return begin(); }
    [[nodiscard]] constexpr const_iterator         cend() const noexcept { return end(); }
    [[nodiscard]] constexpr const_reverse_iterator rbegin() const noexcept { return const_reverse_iterator(begin()); }
    [[nodiscard]] constexpr const_reverse_iterator rend() const noexcept { return const_reverse_iterator(end()); }
    [[nodiscard]] constexpr const_reverse_iterator crbegin() const noexcept { return rbegin(); }
    [[nodiscard]] constexpr const_reverse_iterator crend() const noexcept { return rend(); }

    // capacity
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> size() noexcept;
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> length() noexcept;
    [[nodiscard]] static constexpr std::integral_constant<size_type, N> max_size() noexcept;
    [[nodiscard]] static constexpr std::bool_constant<N == 0>           empty() noexcept;

    // element access
    [[nodiscard]] constexpr const_reference operator[](size_type pos) const RS_FIXED_STRING_CONTRACT_PRE(pos < N) {
        RS_FIXED_STRING_EXPECTS(pos < N);
        return data()[pos];
    }

#if RS_FIXED_STRING_HOSTED
    [[nodiscard]] constexpr const_reference at(size_type pos) const {
        if (pos >= size()) {
            throw std::out_of_range("basic_fixed_string::at");
        }
        return (*this)[pos];
    }
#endif  // RS_FIXED_STRING_HOSTED

    [[nodiscard]] constexpr const_reference front() const RS_FIXED_STRING_CONTRACT_PRE(!empty()) {
        RS_FIXED_STRING_EXPECTS(!empty());
        return (*this)[0];
    }
    [[nodiscard]] constexpr const_reference back() const RS_FIXED_STRING_CONTRACT_PRE(!empty()) {
        RS_FIXED_STRING_EXPECTS(!empty());
        return (*this)[N - 1];
    }

    // modifiers
    constexpr void swap(basic_fixed_string &s) noexcept {
        // element-wise rather than `swap_ranges`: `begin()`/`end()` yield `const_iterator`, so the
        // range algorithms cannot write through them. `data_[N]` is the terminator in both objects.
        for (auto i = 0UZ; i != N; ++i) {
            const CharT tmp = data_[i];
            data_[i]        = s.data_[i];
            s.data_[i]      = tmp;
        }
    }

    // string operations
    [[nodiscard]] constexpr const_pointer c_str() const noexcept { return data(); }
    [[nodiscard]] constexpr const_pointer data() const noexcept { return static_cast<const_pointer>(data_); }
    [[nodiscard]] constexpr std::basic_string_view<CharT, Traits> view() const noexcept {
        return std::basic_string_view<CharT>(cbegin(), cend());
    }

    // NOLINTNEXTLINE (google-explicit-constructor)
    [[nodiscard]] explicit(false) constexpr operator std::basic_string_view<CharT, Traits>() const noexcept {
        return view();
    }
};

// deduction guides
template<typename CharT, std::convertible_to<CharT>... Rest>
basic_fixed_string(CharT, Rest...) -> basic_fixed_string<CharT, 1 + sizeof...(Rest)>;

template<typename CharT, std::size_t N>
basic_fixed_string(const CharT (&str)[N]) -> basic_fixed_string<CharT, N - 1>;

template<typename CharT, std::size_t N>
basic_fixed_string(std::from_range_t, std::array<CharT, N>) -> basic_fixed_string<CharT, N>;

// typedef-names
template<std::size_t N>
using fixed_string = basic_fixed_string<char, N>;
template<std::size_t N>
using fixed_u8string = basic_fixed_string<char8_t, N>;
template<std::size_t N>
using fixed_u16string = basic_fixed_string<char16_t, N>;
template<std::size_t N>
using fixed_u32string = basic_fixed_string<char32_t, N>;
template<std::size_t N>
using fixed_wstring = basic_fixed_string<wchar_t, N>;
}  // namespace risingstarfish

namespace std {
// hash support
template<size_t N>
struct hash<risingstarfish::fixed_string<N>> : hash<string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u8string<N>> : hash<u8string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u16string<N>> : hash<u16string_view> {};
template<size_t N>
struct hash<risingstarfish::fixed_u32string<N>> : hash<u32string_view> {};

// NOTE: We use std::basic_string_view<wchar_t> instead of std::wstring_view because LLVM only makes std::wstring_view
// available when the macro _LIBCPP_HAS_WIDE_CHARACTERS is set to 1. The `wchar_t` type can continue to be used
// without that macro definition. To avoid requiring an additional macro, we simply use std::basic_string_view<wchar_t>,
// which is the underlying definition of std::wstring_view.
template<size_t N>
struct hash<risingstarfish::fixed_wstring<N>> : hash<basic_string_view<wchar_t>> {};

#if RS_FIXED_STRING_HOSTED
// formatting support
template<typename CharT, size_t N, typename Traits>
struct formatter<risingstarfish::basic_fixed_string<CharT, N, Traits>> : formatter<basic_string_view<CharT, Traits>> {
    template<typename FormatContext>
    auto format(const risingstarfish::basic_fixed_string<CharT, N, Traits> &str, FormatContext &ctx) const
      -> decltype(ctx.out()) {
        return formatter<basic_string_view<CharT, Traits>>::format(basic_string_view<CharT, Traits>(str), ctx);
    }
};
#endif
}  // namespace std
>>>>>>> Stashed changes
