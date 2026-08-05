#pragma once


#include <cstdlib>
#include <string>
#include <string_view>

#include "simdjson.h"

namespace dotfiles {

namespace fs = std::filesystem;



constexpr const char default_config[] = {
#embed "../../configs/default.config.json"
  , '\0'};

constexpr const char user_config[] = {
#embed "../../configs/user.config.json"
  , '\0'};


}  // namespace dotfiles