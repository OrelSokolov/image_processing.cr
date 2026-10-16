require "../vips"
require "../mini_magick"

module ImageProcessing
  # The union of values that can flow through builder options, operation
  # arguments and loader/saver option hashes. Crystal does not allow `Object`
  # as a generic type argument, so this alias takes its place.
  alias OptValue = ::Vips::Value | File | Tempfile | Path | ::MiniMagick::Tool |
                   Hash(String, OptValue) | Array(OptValue)

  # Objects an operation block can receive / return (the accumulator of the
  # current processor, or a source path during resize-on-load).
  alias BlockArg = ::Vips::Image | ::MiniMagick::Tool | String

  # Wrapped form of an operation block, stored inside Operation records.
  alias Block = Proc(BlockArg, BlockArg | Nil)

  # Ruby-style truthiness for option values (only nil and false are falsy).
  def self.truthy?(value : OptValue) : Bool
    !value.nil? && value != false
  end

  # Normalizes a value coming from a method_missing-generated call site into
  # an OptValue.
  def self.to_opt(value : Array)
    value.map { |e| to_opt(e).as(OptValue) }
  end

  def self.to_opt(value : Hash)
    hash = {} of String => OptValue
    value.each { |k, v| hash[k.to_s] = to_opt(v) }
    hash
  end

  # GType ids arrive as UInt64 from the Vips bindings; they fit into Int64,
  # which is part of the OptValue union via Vips::Value.
  def self.to_opt(value : UInt64) : OptValue
    value.to_i64
  end

  def self.to_opt(value)
    value.as(OptValue)
  end

  # Converts NamedTuple kwargs (from generated method definitions) into a
  # String-keyed options hash.
  def self.named_to_hash(kwargs : NamedTuple) : Hash(String, OptValue)
    hash = {} of String => OptValue
    kwargs.each { |k, v| hash[k.to_s] = to_opt(v) }
    hash
  end

  # Converts an OptValue into a Vips::Value at the accumulator boundary.
  def self.to_vips_value(value : ::Vips::Value) : ::Vips::Value
    value
  end

  def self.to_vips_value(value : File) : ::Vips::Value
    value.path
  end

  def self.to_vips_value(value : Tempfile) : ::Vips::Value
    value.path
  end

  def self.to_vips_value(value : Path) : ::Vips::Value
    value.to_s
  end

  def self.to_vips_value(value : Array) : ::Vips::Value
    to_vips_values(value.as(Array(OptValue)))
  end

  def self.to_vips_value(value) : ::Vips::Value
    raise Error.new("cannot pass #{value.class} to an image operation")
  end

  def self.to_vips_values(values : Array(OptValue)) : Array(::Vips::Value)
    result = [] of ::Vips::Value
    values.each { |v| result << to_vips_value(v) }
    result
  end

  def self.to_vips_options(options : Hash(String, OptValue)) : Hash(String, ::Vips::Value)
    hash = {} of String => ::Vips::Value
    options.each { |k, v| hash[k] = to_vips_value(v) }
    hash
  end

  # A single image operation: its name, positional arguments (optionally with
  # a trailing String-keyed options hash, mirroring Ruby's kwargs-in-args
  # convention) and an optional block.
  class Operation
    getter name : String
    getter args : Array(OptValue)
    getter block : Block?

    def initialize(@name : String, @args : Array(OptValue) = [] of OptValue,
                   @block : Block? = nil)
    end

    def ==(other : Operation)
      name == other.name && args == other.args && block == other.block
    end

    def inspect : String
      if (b = @block)
        "#<Operation #{name.inspect} #{args.inspect} #{b}>"
      else
        "#<Operation #{name.inspect} #{args.inspect}>"
      end
    end
  end

  # The set of options a pipeline is built from. Mirrors the frozen options
  # Hash that the Ruby version threads through Builder/Pipeline.
  class Options
    property source : OptValue = nil
    property loader : Hash(String, OptValue) = {} of String => OptValue
    property saver : Hash(String, OptValue) = {} of String => OptValue
    property format : String? = nil
    property operations : Array(Operation) = [] of Operation
    property destination : String? = nil
    property instrumenter : Instrumenter? = nil

    def [](key : Symbol) : OptValue | Array(Operation) | String | Hash(String, OptValue) | Instrumenter
      case key
      when :source        then @source
      when :loader        then @loader
      when :saver         then @saver
      when :format        then @format
      when :operations    then @operations
      when :destination   then @destination
      when :instrumenter  then @instrumenter
      else
        raise KeyError.new("invalid option: #{key}")
      end
    end

    def dup : Options
      options = Options.new
      options.source = @source
      options.loader = @loader.dup
      options.saver = @saver.dup
      options.format = @format
      options.operations = @operations.dup
      options.destination = @destination
      options.instrumenter = @instrumenter
      options
    end
  end

  # The instrumenter registered via Chainable#instrumenter (defined after
  # Options, which it references).
  alias Instrumenter = Proc(Options, Proc(Nil), Nil)
end
