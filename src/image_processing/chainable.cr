module ImageProcessing
  # Implements a chainable interface for building processing options. `P` is
  # the processor class, `Acc` its accumulator type. It is both included into
  # Builder and extended into the ImageProcessing::Vips / MiniMagick modules,
  # mirroring Ruby's `extend Chainable`.
  module Chainable(P, Acc)
    # Specify the source image file.
    def source(file) : Builder(P, Acc)
      branch source: ImageProcessing.to_opt(file.as(OptValue))
    end

    # Specify the output format.
    def convert(format : String?) : Builder(P, Acc)
      branch format: format, format_given: true
    end

    # Specify processor options applied when loading the image.
    def loader(**options) : Builder(P, Acc)
      branch loader: ImageProcessing.named_to_hash(options)
    end

    # Specify processor options applied when saving the image.
    def saver(**options) : Builder(P, Acc)
      branch saver: ImageProcessing.named_to_hash(options)
    end

    # Register instrumentation block that will be called around the pipeline.
    # The block receives the pipeline options and a callable that runs the
    # pipeline; its return value is ignored, like in the Ruby version.
    def instrumenter(&instrumenter : Instrumenter) : Builder(P, Acc)
      branch instrumenter: instrumenter, instrumenter_given: true
    end

    # Add multiple operations as a hash or an array.
    #
    #   .apply({resize_to_limit: [400, 400], strip: true})
    #   # or
    #   .apply([{"resize_to_limit", [400, 400]}, {"strip", true}])
    def apply(operations) : Builder(P, Acc)
      builder = current_builder

      pairs = case operations
              when NamedTuple
                operations.map { |name, argument| {name.to_s, argument} }
              when Hash
                operations.map { |name, argument| {name.to_s, argument} }
              when Enumerable
                operations.map { |tuple| {tuple[0].to_s, tuple[1]} }
              else
                raise ArgumentError.new("operations must be a Hash or an Array of pairs")
              end

      pairs.reduce(builder) do |b, pair|
        name, argument = pair
        case argument
        when Nil, true
          apply_operation_to_builder(b, name, [] of OptValue)
        when Array
          apply_operation_to_builder(b, name, argument.map { |v| ImageProcessing.to_opt(v).as(OptValue) })
        when Hash
          apply_operation_to_builder(b, name, [ImageProcessing.to_opt(argument)] of OptValue)
        else
          apply_operation_to_builder(b, name, [ImageProcessing.to_opt(argument).as(OptValue)])
        end
      end
    end

    # Calls the given block with the accumulator object directly. Useful for
    # when you want to access the accumulator object directly. Without a
    # block the operation is a no-op returning the accumulator.
    def custom : Builder(P, Acc)
      branch operations: [Operation.new("custom", [] of OptValue)]
    end

    def custom(&block : Proc(Acc, Acc | Nil)) : Builder(P, Acc)
      wrapped = ->(o : BlockArg) { block.call(o.as(Acc)).as(BlockArg | Nil) }
      branch operations: [Operation.new("custom", [] of OptValue, wrapped)]
    end

    # Creates a stack in the accumulator (MiniMagick parentheses). Generic on
    # Chainable so that the module-function form (`MiniMagick.stack { }`)
    # works without method_missing, which Crystal cannot do for modules.
    def stack(&block : Proc(Acc, Acc | Nil)) : Builder(P, Acc)
      wrapped = ->(o : BlockArg) { block.call(o.as(Acc)).as(BlockArg | Nil) }
      branch operations: [Operation.new("stack", [] of OptValue, wrapped)]
    end

    # Add an operation defined by the processor.
    def operation(name : String, *args, **kwargs, &block : Proc(Acc, Acc | Nil)) : Builder(P, Acc)
      build_operation(name, args, kwargs, block)
    end

    def operation(name : String, *args, **kwargs) : Builder(P, Acc)
      build_operation(name, args, kwargs, nil)
    end

    # Runtime variant used by #apply and the generated bang methods, with
    # already-normalized arguments.
    def operation(name : String, args : Array(OptValue), block : Block? = nil) : Builder(P, Acc)
      branch operations: [Operation.new(name, args, block)]
    end

    # Call the defined processing and get the result. Allows specifying
    # the source file and destination.
    def call(file = nil, *, destination : String? = nil, **call_options)
      builder = current_builder
      builder = builder.branch(source: ImageProcessing.to_opt(file.as(OptValue))) if file
      builder = builder.branch(destination: destination) if destination
      builder.call!(**call_options)
    end

    # Creates a new builder object, merging current options with new options.
    def branch(*, source : OptValue? = nil, loader : Hash(String, OptValue)? = nil,
               saver : Hash(String, OptValue)? = nil, format : String? = nil,
               format_given : Bool = false, operations : Array(Operation)? = nil,
               destination : String? = nil, instrumenter : Instrumenter? = nil,
               instrumenter_given : Bool = false) : Builder(P, Acc)
      base = self.responds_to?(:options) ? self.options.as(Options) : Options.new

      options = base.dup
      options.source = source unless source.nil?
      options.loader = options.loader.merge!(loader || {} of String => OptValue)
      options.saver = options.saver.merge!(saver || {} of String => OptValue)
      options.format = format if format_given
      options.operations = options.operations + (operations || [] of Operation)
      options.destination = destination unless destination.nil?
      options.instrumenter = instrumenter if instrumenter_given

      Builder(P, Acc).new(options)
    end

    private def current_builder : Builder(P, Acc)
      self.responds_to?(:options) ? self.as(Builder(P, Acc)) : branch
    end

    private def apply_operation_to_builder(builder : Builder(P, Acc), name : String,
                                           args : Array(OptValue)) : Builder(P, Acc)
      case name
      when "source"        then builder.source(args[0]?)
      when "convert"       then builder.convert(args[0]?.as?(String))
      when "loader"        then builder.branch(loader: args[0].as(Hash(String, OptValue)))
      when "saver"         then builder.branch(saver: args[0].as(Hash(String, OptValue)))
      else
        builder.operation(name, args)
      end
    end

    private def build_operation(name : String, args : Tuple, kwargs : NamedTuple,
                                block : Proc(Acc, Acc | Nil)?) : Builder(P, Acc)
      op_args = [] of OptValue
      args.each { |a| op_args << ImageProcessing.to_opt(a).as(OptValue) }
      unless kwargs.empty?
        op_args << ImageProcessing.named_to_hash(kwargs)
      end

      wrapped = nil
      if block
        wrapped = ->(o : BlockArg) { block.not_nil!.call(o.as(Acc)).as(BlockArg | Nil) }
      end

      branch operations: [Operation.new(name, op_args, wrapped)]
    end

    # Assume that any unknown method names an operation supported by the
    # processor. Add a bang ("!") if you want processing to be performed.
    #
    # Crystal's method_missing hook cannot generate defs that match calls
    # with named arguments unless the named arguments are spelled out, so
    # they are generated explicitly from the call site.
    macro method_missing(call)
      {% name = call.name.stringify %}
      {% if name =~ /\?$/ %}
        def {{call.name.id}}(*pos_args, **kwargs)
          raise NoMethodError.new("undefined method '{{name.id}}' for #{self.class}")
        end
      {% elsif name =~ /\!$/ && @type.has_method?(name.gsub(/\!$/, "").id) %}
        # Bang form of a real chainable method (e.g. `convert!("png")`):
        # call the method and run the pipeline. Named arguments are spelled
        # out and forwarded, since bare `**kwargs` cannot be generated here.
        {% base = name.gsub(/\!$/, "") %}
        {% forward = call.named_args ? call.named_args.map { |na| "#{na.name.id}: #{na.name.id}" }.join(", ") : "" %}
        {% forward = forward.empty? ? "" : ", " + forward %}
        def {{call.name.id}}(*pos_args{% if call.named_args %}{% for na in call.named_args %}, {{na.name.id}} = nil{% end %}{% end %}{% if call.block %}, &block : Proc(Acc, Acc | Nil){% end %})
          {% if call.block %}
            {{base.id}}(*pos_args{{forward.id}}, &block).call
          {% else %}
            {{base.id}}(*pos_args{{forward.id}}).call
          {% end %}
        end
      {% elsif name =~ /\!$/ %}
        def {{call.name.id}}(*pos_args{% if call.named_args %}{% for na in call.named_args %}, {{na.name.id}} = nil{% end %}{% end %}{% if call.block %}, &block : Proc(Acc, Acc | Nil){% end %})
          op_args = [] of OptValue
          pos_args.each { |a| op_args << ImageProcessing.to_opt(a).as(OptValue) }
          {% if call.named_args && !call.named_args.empty? %}
            kwargs_hash = {} of String => OptValue
            {% for na in call.named_args %}
              kwargs_hash[{{na.name.stringify}}] = ImageProcessing.to_opt({{na.name.id}})
            {% end %}
            # Only append the options hash when a named argument was actually
            # passed; unlike Ruby, generated defs cannot tell "not given"
            # apart from an explicit nil default.
            op_args << kwargs_hash unless kwargs_hash.all? { |_, v| v.nil? }
          {% end %}
          {% if call.block %}
            wrapped = ->(o : BlockArg) { block.call(o.as(Acc)).as(BlockArg | Nil) }
            branch(operations: [Operation.new({{name.gsub(/\!$/, "")}}, op_args, wrapped)]).call
          {% else %}
            branch(operations: [Operation.new({{name.gsub(/\!$/, "")}}, op_args)]).call
          {% end %}
        end
      {% else %}
        def {{call.name.id}}(*pos_args{% if call.named_args %}{% for na in call.named_args %}, {{na.name.id}} = nil{% end %}{% end %}{% if call.block %}, &block : Proc(Acc, Acc | Nil){% end %})
          op_args = [] of OptValue
          pos_args.each { |a| op_args << ImageProcessing.to_opt(a).as(OptValue) }
          {% if call.named_args && !call.named_args.empty? %}
            kwargs_hash = {} of String => OptValue
            {% for na in call.named_args %}
              kwargs_hash[{{na.name.stringify}}] = ImageProcessing.to_opt({{na.name.id}})
            {% end %}
            # Only append the options hash when a named argument was actually
            # passed; unlike Ruby, generated defs cannot tell "not given"
            # apart from an explicit nil default.
            op_args << kwargs_hash unless kwargs_hash.all? { |_, v| v.nil? }
          {% end %}
          {% if call.block %}
            wrapped = ->(o : BlockArg) { block.call(o.as(Acc)).as(BlockArg | Nil) }
            branch operations: [Operation.new({{name}}, op_args, wrapped)]
          {% else %}
            branch operations: [Operation.new({{name}}, op_args)]
          {% end %}
        end
      {% end %}
    end
  end

  # Crystal's `method_missing` hook never fires for class/module-level
  # calls, so the module-function form of the chainable interface
  # (e.g. `ImageProcessing::Vips.resize_to_limit(400, 400)`) has to be
  # generated explicitly from the processor's public operations. This
  # helper lives outside the generic Chainable module because macros of
  # generic modules cannot be resolved via `extend`.
  module ChainableMacros
    macro def_chainable_methods(processor, acc)
      {% processor = processor.resolve %}
      {% for m in processor.methods %}
        {% if m.visibility == :public && !(m.name =~ /([?!]$|_with_block$)/) %}
          def self.{{m.name.id}}(*args, **kwargs, &block : Proc({{acc}}, {{acc}} | Nil))
            operation({{m.name.stringify}}, *args, **kwargs, &block)
          end

          def self.{{m.name.id}}(*args, **kwargs)
            operation({{m.name.stringify}}, *args, **kwargs)
          end
        {% end %}
      {% end %}
    end

    # Generates module-function forms for accumulator operations that are
    # not defined as processor methods (e.g. raw vips operations like
    # "invert" or ImageMagick CLI options like "flip"). On the builder
    # level these go through `method_missing`; module-level calls need
    # explicit definitions.
    macro def_module_operations(ops, acc)
      {% for name in ops %}
        def self.{{name.id}}(*args, **kwargs, &block : Proc({{acc}}, {{acc}} | Nil))
          operation({{name.stringify}}, *args, **kwargs, &block)
        end

        def self.{{name.id}}(*args, **kwargs)
          operation({{name.stringify}}, *args, **kwargs)
        end
      {% end %}
    end

    # Mirrors the Ruby version's method_missing behavior of rejecting
    # predicate methods on the chainable interface.
    macro def_raising_predicates(names)
      {% for name in names %}
        def self.{{name.id}}(*args, **kwargs)
          raise ::ImageProcessing::NoMethodError.new("undefined method '{{name.id}}' for #{self}")
        end
      {% end %}
    end
  end
end
