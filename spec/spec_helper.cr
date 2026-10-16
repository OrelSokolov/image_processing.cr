require "spec"
require "../src/image_processing"

ENV["VIPS_WARNING"] = "0" # disable libvips warnings

module SpecHelpers
  # dhash-style fingerprint (port of the dhash-vips IDHash used by the Ruby
  # test suite): resize to 9x8 grayscale and compare neighboring pixels
  # horizontally and vertically, yielding 128 bits. Both compared images go
  # through the same function, so the distance stays comparable.
  class Fingerprint
    getter rows : UInt64
    getter cols : UInt64

    def initialize(@rows : UInt64, @cols : UInt64)
    end

    def self.of(path : String) : Fingerprint
      wide = gray_bytes(path, "9x8!") # 9 wide, 8 tall -> horizontal diffs
      tall = gray_bytes(path, "8x9!") # 8 wide, 9 tall -> vertical diffs

      rows = 0_u64
      8.times do |y|
        8.times do |x|
          rows |= 1_u64 << (y*8 + x) if wide[y*9 + x + 1] > wide[y*9 + x]
        end
      end

      cols = 0_u64
      8.times do |y|
        8.times do |x|
          cols |= 1_u64 << (y*8 + x) if tall[(y + 1)*8 + x] > tall[y*8 + x]
        end
      end

      new(rows, cols)
    end

    private def self.gray_bytes(path : String, geometry : String) : Array(UInt8)
      stdout = IO::Memory.new
      status = Process.run("magick", [
        path, "-colorspace", "Gray", "-resize", geometry, "-depth", "8", "gray:-",
      ], output: stdout, error: IO::Memory.new)
      raise SpecHelpers::IdentifyError.new("magick failed on #{path}") unless status.success?

      bytes = stdout.to_slice
      raise IdentifyError.new("unexpected grayscale size for #{path}") unless bytes.size == 72
      Array.new(72) { |i| bytes[i] }
    end

    def ^(other : Fingerprint) : Int32
      ((rows ^ other.rows).popcount + (cols ^ other.cols).popcount).to_i
    end
  end

  class IdentifyError < Exception
  end

  def fixture_image(name) : File
    File.open("spec/fixtures/#{name}", "rb")
  end

  def fixture_path(name) : String
    "spec/fixtures/#{name}"
  end

  def copy_to_tempfile(file : File | ImageProcessing::Tempfile, extension : String? = nil) : ImageProcessing::Tempfile
    tempfile = ImageProcessing::Tempfile.new("copy", extension || "")
    File.write(tempfile.path, File.read(file.path))
    tempfile.open
    tempfile
  end

  def tempname(basename : String, extension : String = "") : String
    File.tempname(basename, extension)
  end

  def fingerprint(path : String) : Fingerprint
    Fingerprint.of(path)
  end

  def distance(path1 : String, path2 : String) : Int32
    Fingerprint.of(path1) ^ Fingerprint.of(path2)
  end

  def assert_similar(path1 : String, path2 : String, file = __FILE__, line = __LINE__)
    d = distance(path1, path2)
    fail("expected images to be similar, distance was #{d}", file, line) unless d <= 3
  end

  def refute_similar(path1 : String, path2 : String, file = __FILE__, line = __LINE__)
    d = distance(path1, path2)
    fail("expected images to be different, distance was #{d}", file, line) unless d > 3
  end

  def assert_dimensions(dimensions : Array(Int32), result, file = __FILE__, line = __LINE__)
    path = result.responds_to?(:path) ? result.path : result.to_s
    actual = Vips::Image.new_from_file(path).size
    fail("expected #{dimensions.inspect}, got #{actual.inspect}", file, line) unless actual == dimensions
  end

  def assert_type(type : String, result, file = __FILE__, line = __LINE__)
    path = result.responds_to?(:path) ? result.path : result.to_s
    actual = MiniMagick::Image.new(path).type
    fail("expected #{type}, got #{actual.inspect}", file, line) unless actual == type
  end
end

include SpecHelpers
