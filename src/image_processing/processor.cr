module ImageProcessing
  # Abstract class inherited by individual processors. `Acc` is the
  # accumulator class the processor works with (e.g. Vips::Image or
  # MiniMagick::Tool) — the Crystal equivalent of the Ruby version's
  # `accumulator` macro and `ACCUMULATOR_CLASS` constant.
  abstract class Processor(Acc)
    def self.call(source : BlockArg, loader : Hash(String, OptValue),
                  operations : Array(Operation), saver : Hash(String, OptValue),
                  destination : String? = nil)
      unless source.is_a?(String) || source.is_a?(Acc)
        raise Error.new("invalid source: #{source.inspect}")
      end

      if operations.first?.try(&.name.starts_with?("resize_")) &&
         loader.empty? &&
         supports_resize_on_load?
        accumulator = source
      else
        accumulator = load_image(source, loader)
      end

      operations.each do |operation|
        accumulator = apply_operation(accumulator, operation).as(BlockArg)
      end

      if destination
        save_image(accumulator.as(Acc), destination, saver)
      else
        accumulator
      end
    end

    # Loads the image from source (a path or accumulator object) into the
    # processor's accumulator. Implemented by subclasses.
    def self.load_image(source : BlockArg, loader : Hash(String, OptValue)) : Acc
      raise NotImplementedError.new("#{self} must implement .load_image")
    end

    # Writes the accumulator to the destination path. Implemented by
    # subclasses.
    def self.save_image(image : Acc, path : String, saver : Hash(String, OptValue)) : Nil
      raise NotImplementedError.new("#{self} must implement .save_image")
    end

    # Whether the processor supports resizing the image upon loading.
    def self.supports_resize_on_load? : Bool
      false
    end

    # Delegates to #apply_operation.
    def self.apply_operation(accumulator : BlockArg, operation : Operation)
      new(accumulator).apply_operation(operation.name, operation.args, operation.block)
    end

    @accumulator : BlockArg

    def initialize(@accumulator : BlockArg)
    end

    # Calls the operation to perform the processing. If the operation is
    # defined on the processor (macro), calls the method (dispatch table
    # generated at compile time from the subclass's public methods).
    # Otherwise calls the operation directly on the accumulator object via
    # #run_operation. This provides a common umbrella above defined macros
    # and direct operations.
    def apply_operation(name : String, args : Array(OptValue), block : Block?)
      # Ruby separates trailing kwargs into named arguments; mirror that by
      # popping a trailing options hash off the positional args.
      args = args.dup
      # A trailing options hash is only kwargs when other positional arguments
      # precede it; a lone Hash is a positional argument (e.g. #define, #limits).
      options = if args.size > 1 && args.last?.is_a?(Hash(String, OptValue))
                  args.pop.as(Hash(String, OptValue))
                else
                  {} of String => OptValue
                end

      result = nil
      found = false

      if name == "custom"
        found = true
        result = custom_dispatch(block)
      end

      if name == "composite" && !found
        found = true
        result = block ? composite_dispatch(block, args, options) : composite(args, options)
      end

      {% for method in @type.methods %}
        {% if method.visibility == :public && !["initialize", "apply_operation", "custom", "composite", "composite_with_block"].includes?(method.name.stringify) %}
          if name == {{method.name.stringify}} && !found
            found = true
            result = {{method.name.id}}(args, options)
          end
        {% end %}
      {% end %}

      unless found
        accumulator = @accumulator
        unless accumulator.responds_to?(:run_operation)
          raise NoMethodError.new("#{name.inspect} is not a valid operation")
        end
        result = accumulator.run_operation(name,
          ImageProcessing.to_vips_values(args),
          ImageProcessing.to_vips_options(options), block)
      end

      result.not_nil!
    end

    # Calls the given block with the accumulator object. Useful for when you
    # want to access the accumulator object directly.
    def custom(&block : Proc(Acc, Acc | Nil)) : Acc
      result = block.call(@accumulator.as(Acc))
      result || @accumulator.as(Acc)
    end

    private def custom_dispatch(block : Block?)
      if block
        result = block.call(@accumulator.as(BlockArg))
        result || @accumulator
      else
        @accumulator
      end
    end

    # Dispatches a composite operation that carries a block. Overridden by
    # processors whose accumulator supports it (MiniMagick).
    private def composite_dispatch(block : Block?, args : Array(OptValue),
                                   options : Hash(String, OptValue))
      raise Error.new("composite does not accept a block for this processor")
    end

    # Accumulator accessor, named after the accumulator in the Ruby version
    # ("image" for Vips, "magick" for MiniMagick). Both are provided here as
    # protected methods for parity.
    protected def image : Acc | String
      @accumulator.as(Acc | String)
    end

    protected def magick : Acc | String
      @accumulator.as(Acc | String)
    end
  end
end
