require "json"

module MiniMagick
  # Minimal read-only image info class based on the `identify` CLI,
  # mirroring the parts of mini_magick's MiniMagick::Image that
  # image_processing's test suite exercises (type, exif, data).
  class Image
    def initialize(@path : String)
    end

    def type : String
      identify("-format", "%m", @path)
    end

    def exif : String
      identify("-format", "%[exif:*]", @path)
    end

    # Reads image attributes via -format (this ImageMagick build has no
    # `identify -json` support, so the Ruby gem's #data is approximated by
    # dedicated readers).
    def colorspace : String
      identify("-format", "%[colorspace]", @path)
    end

    def comment : String
      identify("-format", "%c", @path)
    end

    def dimensions : Array(Int32)
      output = identify("-format", "%w %h", @path)
      output.split.map(&.to_i)
    end

    private def identify(*args : String) : String
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run("identify", args.to_a, output: stdout, error: stderr)
      unless status.success?
        raise Error.new("`identify #{args.to_a.join(" ")}` failed: #{stderr}")
      end
      stdout.to_s.chomp("\n")
    end
  end
end
