require "./mini_magick/shell"
require "./mini_magick/tool"
require "./mini_magick/image"

# Crystal equivalent of the subset of the mini_magick gem that
# image_processing relies on: shell execution of ImageMagick commands, the
# Tool command builder and a minimal identify-based Image class.
module MiniMagick
  class Error < Exception
  end

  class_property cli : Symbol = :imagemagick
  class_property cli_prefix : Array(String) = [] of String

  @@imagemagick7 : Bool? = nil

  def self.imagemagick7? : Bool
    @@imagemagick7 ||= begin
      stdout = IO::Memory.new
      status = Process.run("magick", ["-version"], output: stdout, error: IO::Memory.new)
      status.success?
    rescue File::NotFoundError
      false
    end
  end

  def self.imagemagick? : Bool
    cli == :imagemagick
  end

  def self.graphicsmagick? : Bool
    cli == :graphicsmagick
  end

  # Builds a convert tool without executing it (the `convert_shim` of the
  # Ruby version called without a block).
  def self.convert : Tool
    Tool::Convert.new
  end

  # Builds a convert tool, yields it, then executes the command and returns
  # its stdout.
  def self.convert(&block : Tool -> Nil) : String
    tool = Tool::Convert.new
    block.call(tool)
    tool.call
  end
end
