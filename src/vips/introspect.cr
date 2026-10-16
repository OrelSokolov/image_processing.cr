require "./lib_vips"

# Introspection of vips operations: which arguments an operation takes, which
# are required vs optional, and in which direction. This powers both the
# generic operation caller and the "select only options the current loader /
# saver understands" filtering, mirroring ruby-vips' `Vips::Introspect`.
module Vips
  class Introspection
    struct ArgSpec
      getter name : String
      getter gtype : UInt64
      getter priority : Int32

      def initialize(@name : String, @gtype : UInt64, @priority : Int32)
      end
    end

    getter required_input : Array(ArgSpec)   # sorted by priority
    getter optional_input : Hash(String, UInt64)
    getter outputs : Array(ArgSpec)          # required outputs, sorted by priority

    def initialize(@required_input, @optional_input, @outputs)
    end

    # libvips names properties with dashes ("no-rotate"), while Ruby-style
    # callers write underscores ("no_rotate"). Returns the canonical
    # (dashed) option name if the operation accepts it, nil otherwise.
    def canonical_option_name(name : String) : String?
      return name if @optional_input.has_key?(name)
      dashed = name.tr("_", "-")
      dashed if @optional_input.has_key?(dashed)
    end

    def canonical_option_name?(name : String) : Bool
      !canonical_option_name(name).nil?
    end
  end

  module Introspect
    # VipsArgumentFlags
    REQUIRED    = 0x01
    INPUT_FLAG  = 0x10
    OUTPUT_FLAG = 0x20
    DEPRECATED  = 0x40

    @@cache = {} of String => Introspection

    def self.get(name : String) : Introspection
      @@cache[name] ||= introspect(name)
    end

    private def self.introspect(name : String) : Introspection
      Vips.init!
      op = LibVips.vips_operation_new(name)
      raise Error.new("no such operation: #{name}") if op.null?

      begin
        # The first field of any GObject is its class struct.
        oclass = op.as(Pointer(Void*)).value
        n_specs = uninitialized UInt32
        specs = LibVips.g_object_class_list_properties(oclass, pointerof(n_specs))
        raise Error.new("could not list properties of #{name}") if specs.null?

        required_input = [] of Introspection::ArgSpec
        optional_input = {} of String => UInt64
        outputs = [] of Introspection::ArgSpec

        i = 0
        while i < n_specs
          spec = specs[i]
          arg_name = String.new(spec.value.name)
          gtype = spec.value.value_type

          arg_class_ptr = Pointer(LibVips::VipsArgumentClass).null
          pspec = Pointer(LibVips::GParamSpec).null
          arg_instance = Pointer(Void).null

          if LibVips.vips_object_get_argument(op.as(LibVips::VipsObject*), arg_name,
              pointerof(pspec), pointerof(arg_class_ptr), pointerof(arg_instance)) == 0
            arg_class = arg_class_ptr.value
            flags = arg_class.flags
            deprecated = (flags & DEPRECATED) != 0
            is_input = (flags & INPUT_FLAG) != 0
            is_output = (flags & OUTPUT_FLAG) != 0

            unless deprecated
              arg = Introspection::ArgSpec.new(arg_name, gtype, arg_class.priority)
              if (flags & REQUIRED) != 0
                required_input << arg if is_input
                outputs << arg if is_output
              elsif is_input
                optional_input[arg_name] = gtype
              end
            end
          end
          i += 1
        end

        LibVips.g_free(specs.as(Void*))

        required_input.sort_by!(&.priority)
        outputs.sort_by!(&.priority)
        Introspection.new(required_input, optional_input, outputs)
      ensure
        LibVips.g_object_unref(op)
      end
    end
  end
end
