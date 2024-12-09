package triangle

import "core:fmt"
import "base:intrinsics"

try_noval :: proc(#any_int result: u32, loc := #caller_location) {
    if result != 0 {
        fmt.panicf("%v", result, loc = loc)
    }
}

try_withval :: proc(value: $V, #any_int result: u32, loc := #caller_location) -> V {
    if result != 0 do fmt.panicf("%v", result, loc = loc)
    return value
}

try_ok :: proc(value: $V, ok: bool, loc := #caller_location) -> V {
    if !ok do panic("unknown failure", loc = loc)
    return value
}

try_err_nillable :: proc(value: $V, err: $E, loc := #caller_location) -> V 
  where intrinsics.type_is_union(E) {
    if err != nil do fmt.panicf("%v", err, loc = loc)
    return value
}

try_rawptr :: proc(value: rawptr, loc := #caller_location) -> rawptr {
    if value == nil do fmt.panicf("value was nil", loc = loc)
    return value
}

try :: proc { try_noval, try_withval, try_ok, try_err_nillable, try_rawptr }
