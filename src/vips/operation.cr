require "./lib_vips"
require "./gvalue"
require "./introspect"

# Generic vips operation caller: sets required inputs positionally (in
# priority order) and optional inputs from the options hash, builds the
# operation and reads back its first (priority) output. This is the Crystal
# counterpart of ruby-vips' `Vips::Operation.call`, specialized to the
# single-output case which is all image_processing uses.
module Vips
  module Operation
    def self.call(name : String, args : Array(Value),
                  options : Hash(String, Value) = {} of String => Value) : OpResult | Nil
      Vips.init!
      introspection = Introspect.get(name)
      required = introspection.required_input

      unless args.size == required.size
        raise Error.new("#{name}: expected #{required.size} arguments, got #{args.size}")
      end

      op = LibVips.vips_operation_new(name)
      raise Error.new("no such operation: #{name}") if op.null?

      begin
        set_arguments(name, op, introspection, args, options)
      rescue e
        # the operation was never built, so our own reference is the only one
        LibVips.g_object_unref(op)
        raise e
      end

      # vips_cache_operation_build consumes our reference to `op`: on a cache
      # hit it unrefs the fresh operation itself, and on a miss the cache
      # keeps it alive. The returned `built` carries the caller-owned
      # reference instead.
      built = LibVips.vips_cache_operation_build(op)

      if built.null?
        message = String.new(LibVips.vips_error_buffer).strip
        LibVips.vips_error_clear
        raise Error.new(message)
      end

      begin
        out_spec = introspection.outputs.first?
        if out_spec
          result_gval = GValue.new.init(out_spec.gtype)
          LibVips.g_object_get_property(built, out_spec.name, result_gval.to_unsafe)
          result_gval.read
        else
          nil # e.g. save operations, which have no output argument
        end
      ensure
        # drop the references the operation holds on its output arguments;
        # the caller keeps the ones it read out above
        LibVips.vips_object_unref_outputs(built.as(LibVips::VipsObject*))
        # our reference from vips_cache_operation_build
        LibVips.g_object_unref(built)
      end
    end

    # Sets required (positional) and optional (hash) input arguments on the
    # operation.
    private def self.set_arguments(name : String, op : LibVips::VipsOperation*,
                                   introspection : Introspection, args : Array(Value),
                                   options : Hash(String, Value)) : Nil
      introspection.required_input.each_with_index do |spec, i|
        gval = GValue.coerce(spec.gtype, args[i])
        LibVips.g_object_set_property(op, spec.name, gval.to_unsafe)
      end

      options.each do |key, value|
        next if value.nil?
        canonical = introspection.canonical_option_name(key)
        unless canonical
          raise Error.new("#{name}: no such option: #{key}")
        end
        gtype = introspection.optional_input[canonical.not_nil!]
        gval = GValue.coerce(gtype, value)
        LibVips.g_object_set_property(op, canonical.not_nil!, gval.to_unsafe)
      end
    end
  end
end
