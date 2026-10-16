# image_processing.cr

Crystal port of the Ruby [image_processing] gem (v1.14.0): high-level image
processing pipelines for **libvips** and **ImageMagick**.

[image_processing]: https://github.com/janko/image_processing

```crystal
require "image_processing"

processed = ImageProcessing::Vips
  .source(File.open("input.jpg", "rb"))
  .resize_to_limit(800, 800)
  .convert("png")
  .call

processed.path       # => "/tmp/image_processing-…png"
processed.close!
```

## Installation

Add the shard to your `shard.yml`:

```yaml
dependencies:
  image_processing:
    github: OlegSokolov/image_processing.cr
```

The library links against **libvips** (>= 8.6; built and tested with 8.18)
and shells out to **ImageMagick 7** (`magick`/`identify`) for the MiniMagick
processor. Both must be available on the system.

## Vips

```crystal
pipeline = ImageProcessing::Vips
  .source("input.jpg")
  .resize_to_limit(400, 400)
  .saver(quality: 85)
  .convert("png")

result = pipeline.call          # writes to a Tempfile
result = pipeline.call("/path/to/output.png") # or an explicit destination
```

Supported chainable methods mirror the Ruby version: `#source`,
`#convert`, `#loader`, `#saver`, `#instrumenter`, `#apply`, `#custom`,
`#operation`, `#call`, plus all processor operations (`#resize_to_limit`,
`#resize_to_fit`, `#resize_to_fill`, `#resize_and_pad`, `#resize_to_cover`,
`#rotate`, `#composite`, `#set`, `#set_type`, `#set_value`, `#remove`, …).
Appending `!` to an operation runs the pipeline immediately.

Any libvips operation not defined as a processor method falls through to the
accumulator (`Vips::Image`) like ruby-vips' `method_missing` does:

```crystal
ImageProcessing::Vips.invert.call("input.jpg")     # vips "invert" operation
ImageProcessing::Vips.shrink(2, 2).call("input.jpg")
```

## MiniMagick

```crystal
ImageProcessing::MiniMagick
  .source("input.jpg")
  .resize_to_limit(400, 400)
  .convert("png")
  .call
```

Arbitrary ImageMagick CLI options are available the same way (they become
`-option` arguments on the `convert` command):

```crystal
magick = ImageProcessing::MiniMagick
  .source("input.jpg")
  .auto_orient
  .strip
  .call(save: false)   # => MiniMagick::Tool, command not executed
magick.args  # => ["input.jpg", "-auto-orient", "-strip"]
```

## Differences from the Ruby version

The API is a 1:1 port where Crystal allows it. Notable differences:

- The recursive option-value union is typed (`ImageProcessing::OptValue`);
  values that flow through options and operation arguments can be
  `Vips::Value`, `String`, `Int`, `Float`, `Bool`, `Symbol`, `Hash`, `Array`,
  `File`, `Tempfile`, `Path` or `MiniMagick::Tool`.
- Module-level operations (e.g. `ImageProcessing::Vips.invert`) are generated
  at compile time from the processors' public methods, because Crystal's
  `method_missing` hook does not fire for module-level calls.
- Builder-level unknown operations go through `method_missing`, which cannot
  accept arbitrary named arguments; named arguments used at a call site are
  compiled into the generated method, and a trailing options `Hash` can
  always be passed positionally instead.
- `libvips` 8.18 removed the `add_alpha` and `composite2` operations; the
  port implements `#add_alpha` via `bandjoin_const` and `#composite` via the
  unified `composite` operation. `saver(strip: true)` transparently maps to
  the `keep` flags on libvips >= 8.15.

## Development

```
crystal spec        # full suite (compilation takes a few minutes)
```

The test suite is a port of the upstream Ruby tests (dhash-similarity
assertions included). A few assertions are adapted for libvips 8.18 /
ImageMagick 7 behavior; each deviation is marked with a comment in the spec.

## License

MIT, same as the original gem.
