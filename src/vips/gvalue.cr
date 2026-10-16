require "./lib_vips"

# GValue marshalling: converts Crystal values into typed GValues based on the
# GType of the operation argument being set, and reads GValues back into
# Crystal values. This mirrors ruby-vips' `Vips::GValue` logic.
module Vips
  # Fundamental GType ids (gtype.h, ABI-stable).
  G_TYPE_INVALID  =  0_u64
  G_TYPE_NONE     =  4_u64
  G_TYPE_INTERFACE = 8_u64
  G_TYPE_CHAR     = 12_u64
  G_TYPE_UCHAR    = 16_u64
  G_TYPE_BOOLEAN  = 20_u64
  G_TYPE_INT      = 24_u64
  G_TYPE_UINT     = 28_u64
  G_TYPE_LONG     = 32_u64
  G_TYPE_ULONG    = 36_u64
  G_TYPE_INT64    = 40_u64
  G_TYPE_UINT64   = 44_u64
  G_TYPE_ENUM     = 48_u64
  G_TYPE_FLAGS    = 52_u64
  G_TYPE_FLOAT    = 56_u64
  G_TYPE_DOUBLE   = 60_u64
  G_TYPE_STRING   = 64_u64
  G_TYPE_POINTER  = 68_u64
  G_TYPE_BOXED    = 72_u64
  G_TYPE_PARAM    = 76_u64
  G_TYPE_OBJECT   = 80_u64
  G_TYPE_VARIANT  = 84_u64

  class GValue
    @value = LibVips::GValue.new(g_type: 0_u64, data: UInt64.static_array(0_u64, 0_u64))
    @initialized = false

    # Blob payloads must outlive the GValue (vips keeps referencing the data
    # pointer), so pinned allocations are retained for the process lifetime.
    @@pinned = [] of Pointer(UInt8)

    def to_unsafe : LibVips::GValue*
      pointerof(@value)
    end

    def init(gtype : UInt64) : self
      LibVips.g_value_init(to_unsafe, gtype)
      @initialized = true
      self
    end

    # Marks the value as owning content after C code filled it in-place
    # (e.g. vips_image_get), so that #finalize unsets it.
    def mark_filled : self
      @initialized = true
      self
    end

    def finalize
      LibVips.g_value_unset(to_unsafe) if @initialized
    end

    def set_boolean(v : Bool) : Nil
      LibVips.g_value_set_boolean(to_unsafe, v ? 1 : 0)
    end

    def set_int(v : Int32) : Nil
      LibVips.g_value_set_int(to_unsafe, v)
    end

    def set_uint(v : UInt32) : Nil
      LibVips.g_value_set_uint(to_unsafe, v)
    end

    def set_long(v : Int64) : Nil
      LibVips.g_value_set_long(to_unsafe, v)
    end

    def set_ulong(v : UInt64) : Nil
      LibVips.g_value_set_ulong(to_unsafe, v)
    end

    def set_int64(v : Int64) : Nil
      LibVips.g_value_set_int64(to_unsafe, v)
    end

    def set_uint64(v : UInt64) : Nil
      LibVips.g_value_set_uint64(to_unsafe, v)
    end

    def set_double(v : Float64) : Nil
      LibVips.g_value_set_double(to_unsafe, v)
    end

    def set_float(v : Float32) : Nil
      LibVips.g_value_set_float(to_unsafe, v)
    end

    def set_string(v : String) : Nil
      LibVips.g_value_set_string(to_unsafe, v)
    end

    def set_enum(v : Int32) : Nil
      LibVips.g_value_set_enum(to_unsafe, v)
    end

    def set_flags(v : Int32) : Nil
      LibVips.g_value_set_flags(to_unsafe, v)
    end

    def set_object(ptr : Void*) : Nil
      LibVips.g_value_set_object(to_unsafe, ptr)
    end

    def set_boxed(ptr : Void*) : Nil
      LibVips.g_value_set_boxed(to_unsafe, ptr)
    end

    # Reads the GValue back into a Crystal value (Image for VipsImage
    # properties, scalars for everything else commonly used).
    def read : OpResult
      gtype = @value.g_type
      case LibVips.g_type_fundamental(gtype)
      when .==(G_TYPE_STRING) then String.new(LibVips.g_value_get_string(to_unsafe))
      when .==(G_TYPE_BOOLEAN) then LibVips.g_value_get_boolean(to_unsafe) != 0
      when .==(G_TYPE_INT) then LibVips.g_value_get_int(to_unsafe)
      when .==(G_TYPE_INT64) then LibVips.g_value_get_int64(to_unsafe)
      when .==(G_TYPE_DOUBLE) then LibVips.g_value_get_double(to_unsafe)
      when .==(G_TYPE_ENUM) then LibVips.g_value_get_enum(to_unsafe)
      when .==(G_TYPE_OBJECT)
        ptr = LibVips.g_value_get_object(to_unsafe)
        if ptr && gtype == Vips.image_type
          # own a reference for the wrapper's finalizer
          LibVips.g_object_ref(ptr)
          Image.new(ptr.as(LibVips::VipsImage*))
        else
          raise Error.new("unsupported object GValue (#{Vips.type_name(gtype)})")
        end
      when .==(G_TYPE_BOXED)
        read_boxed(gtype)
      else
        raise Error.new("unsupported GValue type #{Vips.type_name(gtype)}")
      end
    end

    private def read_boxed(gtype : UInt64) : String
      boxed = LibVips.g_value_get_boxed(to_unsafe)
      case gtype
      when .==(Vips.ref_string_type)
        len = uninitialized Int32
        str = LibVips.vips_ref_string_get(boxed, pointerof(len))
        String.new(str, len)
      when .==(Vips.blob_type)
        size = uninitialized UInt64
        data = LibVips.vips_blob_get(boxed, pointerof(size))
        String.new(data, size)
      else
        raise Error.new("unsupported boxed GValue type #{Vips.type_name(gtype)}")
      end
    end

    # Coerces a Crystal value into a GValue of the given GType. Values arrive
    # as `Object` because they flow in from user-supplied option hashes.
    def self.coerce(gtype : UInt64, value : Value) : GValue
      gval = GValue.new.init(gtype)

      case LibVips.g_type_fundamental(gtype)
      when .==(G_TYPE_STRING)
        case value
        when String then gval.set_string(value)
        when Symbol then gval.set_string(value.to_s)
        else raise Error.new("expected String for #{Vips.type_name(gtype)}, got #{value.class}")
        end
      when .==(G_TYPE_BOOLEAN)
        case value
        when Bool then gval.set_boolean(value)
        else raise Error.new("expected Bool for #{Vips.type_name(gtype)}, got #{value.class}")
        end
      when .==(G_TYPE_INT)
        gval.set_int(Vips.to_i(value))
      when .==(G_TYPE_UINT)
        gval.set_uint(Vips.to_i(value).to_u32)
      when .==(G_TYPE_LONG)
        gval.set_long(Vips.to_i(value).to_i64)
      when .==(G_TYPE_ULONG)
        gval.set_ulong(Vips.to_i(value).to_u64)
      when .==(G_TYPE_INT64)
        gval.set_int64(Vips.to_i(value).to_i64)
      when .==(G_TYPE_UINT64)
        gval.set_uint64(Vips.to_i(value).to_u64)
      when .==(G_TYPE_FLOAT)
        gval.set_float(Vips.to_f(value).to_f32)
      when .==(G_TYPE_DOUBLE)
        gval.set_double(Vips.to_f(value))
      when .==(G_TYPE_ENUM)
        gval.set_enum(Vips.enum_value(gtype, value))
      when .==(G_TYPE_FLAGS)
        gval.set_flags(Vips.flags_value(gtype, value))
      when .==(G_TYPE_OBJECT)
        case value
        when Image
          unless gtype == Vips.image_type
            raise Error.new("expected #{Vips.type_name(gtype)} object, got #{value.class}")
          end
          gval.set_object(value.to_unsafe.as(Void*))
        else raise Error.new("expected Vips::Image for #{Vips.type_name(gtype)}, got #{value.class}")
        end
      when .==(G_TYPE_BOXED)
        coerce_boxed(gval, gtype, value)
      else
        raise Error.new("unsupported argument type #{Vips.type_name(gtype)}")
      end

      gval
    end

    def self.coerce_boxed(gval : GValue, gtype : UInt64, value : Value) : Nil
      case gtype
      when .==(Vips.array_double_type)
        doubles = [] of Float64
        each_element(value) do |e|
          doubles << Vips.to_f(e)
        end
        ptr = LibVips.vips_array_double_new(doubles.to_unsafe, doubles.size)
        gval.set_boxed(ptr)
      when .==(Vips.array_int_type)
        ints = [] of Int32
        each_element(value) do |e|
          ints << Vips.to_i(e)
        end
        ptr = LibVips.vips_array_int_new(ints.to_unsafe, ints.size)
        gval.set_boxed(ptr)
      when .==(Vips.array_image_type)
        images = [] of LibVips::VipsImage*
        each_element(value) do |e|
          unless e.is_a?(Image)
            raise Error.new("expected Vips::Image in VipsArrayImage, got #{e.class}")
          end
          images << e.to_unsafe
        end
        ptr = LibVips.vips_array_image_new(images.to_unsafe, images.size)
        gval.set_boxed(ptr)
      when .==(Vips.blob_type)
        str = value.to_s
        # The data must outlive the blob (vips keeps referencing the data
        # pointer), so the payload copy is pinned for the process lifetime.
        data = Pointer(UInt8).malloc(str.bytesize)
        data.copy_from(str.to_unsafe, str.bytesize)
        @@pinned << data
        ptr = LibVips.vips_blob_new(Pointer(Void).null, data, str.bytesize)
        gval.set_boxed(ptr)
      else
        raise Error.new("unsupported boxed type #{Vips.type_name(gtype)}")
      end
    end

    private def self.each_element(value : Value, &block : Value -> Nil) : Nil
      unless value.is_a?(Array)
        raise Error.new("expected Array for boxed argument, got #{value.class}")
      end
      value.each do |e|
        yield e.as(Value)
      end
    end
  end
end
