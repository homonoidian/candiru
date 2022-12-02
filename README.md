# Candiru

> Candiru "are known for an alleged tendency to invade and
> parasitise the human urethra" -- Wikipedia

A wrapper around `Crystal::FFI`, written mainly to learn the latter.

## Associative series

Very experimental. May break and already broke a few times. Get used
to segfaults. A lot TODO. Too complex. Still requires casts from time
to time (the sole reason why it was written is to avoid them)

## Example

Please see the examples folder.

```crystal
point_struct = Candiru::StructScaffold[Int32, Int32]

point = point_struct.new { |s| s << 1; s << 2 }

my_fancy_c_func = Candiru::Fn.new(handle, [point_struct])
my_fancy_c_func.call(point)

# ... stuff like this
```
