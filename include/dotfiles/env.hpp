#pragma once


#include <cstdlib>
#include <string>
#include <string_view>

#include "simdjson.h"

namespace dotfiles {

constexpr const char user_config[] = CONFIG_JSON "\0";

}  // namespace dotfiles