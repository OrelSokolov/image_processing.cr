require "./vips/lib_vips"
require "./vips/gvalue"
require "./vips/introspect"
require "./vips/operation"
require "./vips/image"

# Crystal equivalent of the subset of the ruby-vips gem that image_processing
# relies on: libvips initialization, GType helpers, enum translation and
# loader/saver lookup.
module Vips
  class Error < Exception
  end

  # The union of values that can flow into vips operation arguments and
  # options. Crystal does not allow `Object` as a generic type argument, so
  # this alias takes its place across the binding.
  alias Value = Nil | Bool | Int32 | Int64 | Float32 | Float64 | String | Symbol |
              Array(Value) | Array(Image) | Image

  # The union of values a vips operation can return.
  alias OpResult = Bool | Float64 | Int32 | Int64 | String | Image


  # Coordinate value that means "unlimited" for thumbnail dimensions.
  MAX_COORD = 10_000_000

  # GType of VipsBlob (same as ruby-vips' Vips::BLOB_TYPE). The type is only
  # registered once libvips is initialized, so resolve it lazily on first
  # access (Crystal constants with runtime initializers are deferred).
  BLOB_TYPE = begin
    init!
    gtype = LibVips.g_type_from_name("VipsBlob")
    raise Error.new("unknown type: VipsBlob") if gtype == 0
    gtype
  end

  @@initialized = false

  def self.init! : Nil
    unless @@initialized
      LibVips.vips_init("image_processing.cr")
      @@initialized = true
    end
  end

  def self.version : Array(Int32)
    init!
    (0..2).map { |flag| LibVips.vips_version(flag) }
  end

  def self.at_least_libvips?(major : Int32, minor : Int32) : Bool
    init!
    v_major = LibVips.vips_version(0)
    v_minor = LibVips.vips_version(1)
    v_major > major || (v_major == major && v_minor >= minor)
  end

  @@image_type : UInt64? = nil
  @@array_double_type : UInt64? = nil
  @@array_int_type : UInt64? = nil
  @@array_image_type : UInt64? = nil
  @@ref_string_type : UInt64? = nil
  @@blob_type : UInt64? = nil

  def self.image_type : UInt64
    @@image_type ||= LibVips.vips_image_get_type
  end

  def self.array_double_type : UInt64
    @@array_double_type ||= LibVips.vips_array_double_get_type
  end

  def self.array_int_type : UInt64
    @@array_int_type ||= LibVips.vips_array_int_get_type
  end

  def self.array_image_type : UInt64
    @@array_image_type ||= LibVips.vips_array_image_get_type
  end

  def self.ref_string_type : UInt64
    @@ref_string_type ||= LibVips.vips_ref_string_get_type
  end

  def self.blob_type : UInt64
    @@blob_type ||= LibVips.vips_blob_get_type
  end

  def self.type_from_name(name : String) : UInt64
    gtype = LibVips.g_type_from_name(name)
    raise Error.new("unknown type: #{name}") if gtype == 0
    gtype
  end

  def self.type_name(gtype : UInt64) : String
    name = LibVips.g_type_name(gtype)
    name.null? ? "GType(#{gtype})" : String.new(name)
  end

  # Translates an enum member given as Symbol/String into its integer value.
  def self.enum_value(gtype : UInt64, value : Value) : Int32
    case value
    when Int32 then value
    when Int64 then value.to_i32
    else
      enum_class = LibVips.g_type_class_ref(gtype)
      begin
        gev = LibVips.g_enum_get_value_by_nick(enum_class, value.to_s)
        raise Error.new("invalid enum value '#{value}' for #{type_name(gtype)}") if gev.null?
        gev.value.value
      ensure
        LibVips.g_type_class_unref(enum_class)
      end
    end
  end

  # Translates a flags member given as Symbol/String into its integer value.
  def self.flags_value(gtype : UInt64, value : Value) : Int32
    case value
    when Int32 then value
    when Int64 then value.to_i32
    else
      flags_class = LibVips.g_type_class_ref(gtype)
      begin
        gfv = LibVips.g_flags_get_value_by_nick(flags_class, value.to_s)
        raise Error.new("invalid flags value '#{value}' for #{type_name(gtype)}") if gfv.null?
        gfv.value.value
      ensure
        LibVips.g_type_class_unref(flags_class)
      end
    end
  end

  # Translates an enum integer back into its nickname.
  def self.enum_nick(gtype : UInt64, value : Int32) : String
    enum_class = LibVips.g_type_class_ref(gtype)
    begin
      gev = LibVips.g_enum_get_value(enum_class, value)
      raise Error.new("invalid enum value #{value} for #{type_name(gtype)}") if gev.null?
      String.new(gev.value.value_nick)
    ensure
      LibVips.g_type_class_unref(enum_class)
    end
  end

  def self.to_i(value : Value) : Int32
    case value
    when Int32 then value
    when Int64 then value.to_i32
    when Float64 then value.round.to_i32
    when Float32 then value.round.to_i32
    else raise Error.new("expected an integer, got #{value.class}")
    end
  end

  def self.to_f(value : Value) : Float64
    case value
    when Float64 then value
    when Float32 then value.to_f64
    when Int32 then value.to_f64
    when Int64 then value.to_f64
    else raise Error.new("expected a number, got #{value.class}")
    end
  end

  def self.kwargs_to_hash(kwargs : NamedTuple) : Hash(String, Value)
    options = {} of String => Value
    kwargs.each do |key, value|
      options[key.to_s] = case value
                          when Array
                            value.map { |e| e.as(Value) }
                          else
                            value.as(Value)
                          end
    end
    options
  end

  def self.foreign_find_load(path : String) : String?
    init!
    nickname = LibVips.vips_foreign_find_load(path)
    nickname.null? ? nil : String.new(nickname)
  end

  def self.foreign_find_save(path : String) : String?
    init!
    nickname = LibVips.vips_foreign_find_save(path)
    nickname.null? ? nil : String.new(nickname)
  end
end
