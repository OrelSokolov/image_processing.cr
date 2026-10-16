module MiniMagick
  # Wraps an ImageMagick command-line tool: accumulates CLI arguments and
  # executes them, mirroring mini_magick's MiniMagick::Tool.
  class Tool
    getter name : String
    getter args : Array(String)

    def initialize(@name : String)
      @args = [] of String
    end

    def self.new(*args, **options, &block : self -> Nil)
      instance = new(*args, **options)
      block.call(instance)
      instance.call
      instance
    end

    # Executes the command that has been built up.
    def call(**options) : String
      stdout, _, _ = Shell.run(command)
      stdout.chomp("\n")
    end

    # The currently built-up command.
    def command : Array(String)
      executable + args
    end

    # The executable used for this tool.
    def executable : Array(String)
      exe = MiniMagick.cli_prefix.dup
      exe << "magick" if MiniMagick.imagemagick7? && @name != "magick"
      exe << "gm" if MiniMagick.graphicsmagick?
      exe << @name
      exe
    end

    # Appends raw options, useful for appending image paths.
    def <<(arg) : self
      @args << arg.to_s
      self
    end

    # Merges a list of raw options.
    def merge!(new_args) : self
      new_args.each { |arg| self << arg }
      self
    end

    # Changes the last operator to its "plus" form, e.g. "-strip" to
    # "+strip". This is the port of mini_magick's Tool#+. Zero-argument
    # overloads are spelled out because a restricted splat does not match
    # calls without arguments, which would fall through to method_missing.
    def plus : self
      @args[-1] = @args[-1].sub(/^-/, "+")
      self
    end

    def plus(*values : String) : self
      plus
      merge!(values)
    end

    # :ditto:
    def + : self
      plus
    end

    # :ditto:
    def +(*values : String) : self
      plus(*values)
    end

    # Creates an ImageMagick stack (parentheses) in the command.
    def stack(*args, &block : self -> Nil) : self
      self << "("
      args.each do |value|
        case value
        when Hash
          value.each do |key, v|
            option(key.to_s, v.is_a?(Array) ? v.map(&.to_s) : [v.to_s])
          end
        when String then self << value
        end
      end
      yield self
      self << ")"
      self
    end

    def stack(*args) : self
      stack(*args) { |stack| stack }
    end

    # Adds ImageMagick's pseudo-filename `-` for standard input.
    def stdin : self
      self << "-"
    end

    # Adds ImageMagick's pseudo-filename `-` for standard output.
    def stdout : self
      self << "-"
    end

    # This option is a valid ImageMagick option, but it's also a common
    # method name, so it's defined explicitly to act as an option method.
    def clone(*args) : self
      self << "-clone"
      merge!(args.map(&.to_s).to_a)
      self
    end

    # Runtime application of an option ("name" + optional values), used by
    # ImageProcessing's loader/saver option handling. Equivalent to what the
    # generated option methods do.
    def option(name : String, values : Array = [] of String) : self
      self << "-#{name.tr("_", "-")}"
      values.each { |value| self << value.to_s }
      self
    end

    # Dispatches an arbitrary operation by name at runtime (the accumulator
    # side of ImageProcessing's operation application).
    def run_operation(name : String, args : Array(::Vips::Value),
                      options : Hash(String, ::Vips::Value),
                      block : Proc(::Vips::Image | ::MiniMagick::Tool | String,
                                   ::Vips::Image | ::MiniMagick::Tool | String | Nil)? = nil) : self
      case name
      when "stack"
        blk = block || raise ::ImageProcessing::Error.new("stack requires a block")
        stack { |tool| blk.call(tool); nil }
        self
      else
        option(name, args.map(&.to_s))
      end
    end

    # Creation operators.
    {% for operator in %w(xc canvas logo rose gradient radial-gradient plasma pattern text pango) %}
      def {{operator.tr("-", "_").id}}(value = nil) : self
        self << "{{operator.id}}:#{value}"
        self
      end
    {% end %}

    # Any undefined method will be transformed into a CLI option.
    macro method_missing(call)
      {% name = call.name.stringify %}
      {% if name =~ /[\?!]/ || call.block %}
        def {{call.name.id}}(*args, **kwargs)
          raise ::ImageProcessing::NoMethodError.new("undefined method '{{name.id}}' for #{self.class}")
        end
      {% else %}
        def {{call.name.id}}(*args) : self
          option({{name}}, args.map(&.to_s).to_a)
        end
      {% end %}
    end
  end

  # Tool subclasses, mirroring mini_magick's Tool::Convert etc.
  class Tool
    {% for tool in %w(animate compare composite conjure convert display identify import magick mogrify montage stream) %}
      class {{tool.capitalize.id}} < ::MiniMagick::Tool
        def initialize
          super({{tool}})
        end
      end
    {% end %}
  end
end
