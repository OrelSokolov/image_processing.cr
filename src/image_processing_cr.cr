require "./image_processing/version"
require "./image_processing/tempfile"
require "./image_processing/options"
require "./image_processing/chainable"
require "./image_processing/builder"
require "./image_processing/pipeline"
require "./image_processing/processor"
require "./vips"
require "./mini_magick"

module ImageProcessing
  class Error < Exception
  end

  # Crystal has no built-in NoMethodError; the Ruby version lets NoMethodError
  # propagate for unknown predicate methods on the chainable interface, so an
  # equivalent exception is provided.
  class NoMethodError < Exception
  end
end

require "./image_processing/vips"
require "./image_processing/mini_magick"
