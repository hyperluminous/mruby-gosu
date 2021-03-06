#pragma once

#include "mruby.h"
#include "mruby/data.h"
#include "mruby/proc.h"
#include "mruby/class.h"
#include "mruby/string.h"
#include "mruby/array.h"
#include "stdbool.h"
#include "string.h"
#include <Gosu/Image.h>

struct RClass *mrb_gosu_image;

void mrb_gosu_image_init(mrb_state *mrb, struct RClass *mrb_gosu);
Gosu_Image *mrb_gosu_image_get_ptr(mrb_state *mrb, mrb_value self);