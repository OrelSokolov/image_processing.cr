require "./lib_vips"
require "./gvalue"
require "./operation"

# Wrapper around a VipsImage pointer. Owns one reference (released by the
# finalizer) unless told otherwise. Exposes the API surface that both
# image_processing pipelines and direct users need; unknown method names
# become vips operations invoked on the image (like ruby-vips does).
module Vips
  class Image
    # Releases the underlying VipsImage reference when collected.
    private class Ref
      def initialize(@ptr : LibVips::VipsImage*)
      end

      def finalize
        LibVips.g_object_unref(@ptr)
      end
    end

    # Anchors the finalizer token for as long as this wrapper is reachable;
    # without it Boehm would consider the Ref unreachable and run its
    # finalizer (dropping the reference) while the wrapper is still in use.
    @ref : Ref?

    def initialize(@ptr : LibVips::VipsImage*, take_ownership : Bool = true)
      if take_ownership
        @ref = Ref.new(@ptr)
        GC.add_finalizer(@ref)
      end
    end

    def to_unsafe : LibVips::VipsImage*
      @ptr
    end


    def self.new_from_file(path : String, **options) : Image
      new_from_file(path, Vips.kwargs_to_hash(options))
    end

    # Loads an image from disk using the operation that libvips picks for the
    # filename (e.g. "jpegload"). Raises Vips::Error for unknown formats.
    def self.new_from_file(path : String, options : Hash(String, Value)) : Image
      Vips.init!
      loader = LibVips.vips_foreign_find_load(path)
      raise Error.new("#{path} is not a known file format") if loader.null?
      Operation.call(String.new(loader), [path] of Value, options).as(Image)
    end

    def self.thumbnail(filename : String, width : Int32?, height : Int32? = nil, **options) : Image
      thumbnail(filename, width, height, Vips.kwargs_to_hash(options))
    end

    def self.thumbnail(filename : String, width : Int32?, height : Int32?,
                       options : Hash(String, Value)) : Image
      opts = options.dup
      opts["height"] = height if height
      Operation.call("thumbnail", [filename, width] of Value, opts).as(Image)
    end

    def self.new_from_array(array : Array, scale : Int32 = 1) : Image
      flat = [] of Float64
      array.each do |row|
        row.as(Array).each do |value|
          flat << case value
                  when Int32 then value.to_f64
                  when Int64 then value.to_f64
                  when Float64 then value
                  when Float32 then value.to_f64
                  else raise Error.new("invalid array element: #{value.inspect}")
                  end
        end
      end
      width = array.size
      height = array.first.as(Array).size
      Vips.init!
      ptr = LibVips.vips_image_new_matrix_from_array(width, height, flat.to_unsafe, flat.size)
      raise Error.new("could not create image from array") if ptr.null?
      image = Image.new(ptr)
      image.set("scale", scale.to_f64)
      image
    end

    def thumbnail_image(width : Int32?, height : Int32? = nil, **options) : Image
      thumbnail_image(width, height, Vips.kwargs_to_hash(options))
    end

    def thumbnail_image(width : Int32?, height : Int32?,
                        options : Hash(String, Value)) : Image
      opts = options.dup
      opts["height"] = height if height
      Operation.call("thumbnail_image", [self, width] of Value, opts).as(Image)
    end

    def autorot : Image
      Operation.call("autorot", [self] of Value).as(Image)
    end

    def conv(mask : Image, **options) : Image
      conv(mask, Vips.kwargs_to_hash(options))
    end

    def conv(mask : Image, options : Hash(String, Value)) : Image
      Operation.call("conv", [self, mask] of Value, options).as(Image)
    end

    def gravity(direction : Symbol | String, width : Int32, height : Int32, **options) : Image
      gravity(direction, width, height, Vips.kwargs_to_hash(options))
    end

    def gravity(direction : Symbol | String, width : Int32, height : Int32,
                options : Hash(String, Value)) : Image
      Operation.call("gravity", [self, direction, width, height] of Value, options).as(Image)
    end

    # libvips removed the dedicated "add_alpha" operation; append a constant
    # band holding the maximum alpha value of the image's format.
    def add_alpha : Image
      constant = case format
                 when "float", "double", "complex", "dpcomplex" then 1.0
                 when "ushort", "short"                          then 65535.0
                 else                                                 255.0
                 end
      Operation.call("bandjoin_const", [self, [constant] of Value] of Value).as(Image)
    end

    def has_alpha? : Bool
      LibVips.vips_image_hasalpha(@ptr) != 0
    end

    def similarity(**options) : Image
      similarity(Vips.kwargs_to_hash(options))
    end

    def similarity(options : Hash(String, Value)) : Image
      Operation.call("similarity", [self] of Value, options).as(Image)
    end

    def rot(angle : Symbol | String) : Image
      Operation.call("rot", [self, angle] of Value).as(Image)
    end

    def rot90 : Image
      rot(:d90)
    end

    def rot180 : Image
      rot(:d180)
    end

    def rot270 : Image
      rot(:d270)
    end

    def composite(overlay : Image, mode, **options) : Image
      composite([overlay], mode, Vips.kwargs_to_hash(options))
    end

    def composite(overlay : Image, mode, options : Hash(String, Value)) : Image
      composite([overlay], mode, options)
    end

    def composite(overlays : Array(Image), mode, **options) : Image
      composite(overlays, mode, Vips.kwargs_to_hash(options))
    end

    def composite(overlays : Array(Image), mode,
                  options : Hash(String, Value)) : Image
      blend_type = Vips.type_from_name("VipsBlendMode")
      modes = mode.is_a?(Array) ? mode : Array.new(overlays.size, mode)
      mode_ints = [] of Value
      modes.each do |m|
        mode_ints << (m.is_a?(Int32) ? m : Vips.enum_value(blend_type, m.as(Value)))
      end
      Operation.call("composite", [overlays, mode_ints] of Value, options).as(Image)
    end

    def write_to_file(path : String, **options) : Nil
      write_to_file(path, Vips.kwargs_to_hash(options))
    end

    def write_to_file(path : String, options : Hash(String, Value)) : Nil
      Vips.init!
      saver = LibVips.vips_foreign_find_save(path)
      raise Error.new("#{path} is not a known file format") if saver.null?
      Operation.call(String.new(saver), [self, path] of Value, options)
      nil
    end

    def avg : Float64
      Operation.call("avg", [self] of Value).as(Float64)
    end

    def copy : Image
      Operation.call("copy", [self] of Value).as(Image)
    end

    # -- metadata --

    def set(name : String, value : Value) : Nil
      gval = case value
             when String then GValue.new.init(G_TYPE_STRING).tap(&.set_string(value))
             when Bool then GValue.new.init(G_TYPE_BOOLEAN).tap(&.set_boolean(value))
             when Int32 then GValue.new.init(G_TYPE_INT).tap(&.set_int(value))
             when Int64 then GValue.new.init(G_TYPE_INT64).tap(&.set_int64(value))
             when Float64 then GValue.new.init(G_TYPE_DOUBLE).tap(&.set_double(value))
             else raise Error.new("unsupported metadata value: #{value.class}")
             end
      LibVips.vips_image_set(@ptr, name, gval.to_unsafe)
    end

    def set_type(gtype : UInt64, name : String, value : Value) : Nil
      gval = GValue.coerce(gtype, value)
      LibVips.vips_image_set(@ptr, name, gval.to_unsafe)
    end

    def set_value(name : String, value : Value) : Nil
      set(name, value)
    end

    def remove(name : String) : Bool
      LibVips.vips_image_remove(@ptr, name) != 0
    end

    def get(name : String) : OpResult
      gval = GValue.new
      if LibVips.vips_image_get(@ptr, name, gval.to_unsafe) != 0
        LibVips.vips_error_clear
        raise Error.new("field '#{name}' not found")
      end
      gval.mark_filled.read
    end

    def get_fields : Array(String)
      strv = LibVips.vips_image_get_fields(@ptr)
      fields = [] of String
      i = 0
      while !strv[i].null?
        fields << String.new(strv[i])
        i += 1
      end
      LibVips.g_strfreev(strv)
      fields
    end

    # -- geometry --

    def width : Int32
      LibVips.vips_image_get_width(@ptr)
    end

    def height : Int32
      LibVips.vips_image_get_height(@ptr)
    end

    def bands : Int32
      LibVips.vips_image_get_bands(@ptr)
    end

    def size : Array(Int32)
      [width, height]
    end

    def format : String
      band_format = LibVips.vips_image_get_format(@ptr)
      Vips.enum_nick(Vips.type_from_name("VipsBandFormat"), band_format)
    end

    # Dispatches an arbitrary operation with `self` as the first input, used
    # by ImageProcessing::Processor for operations not defined above.
    def run_operation(name : String, args : Array(Value),
                      options : Hash(String, Value),
                      block : Proc(::Vips::Image | ::MiniMagick::Tool | String,
                                   ::Vips::Image | ::MiniMagick::Tool | String | Nil)? = nil) : OpResult | Nil
      # libvips removed the convenience rot90/rot180/rot270 operations;
      # translate them to the "rot" operation with the matching angle.
      case name
      when "add_alpha"
        return add_alpha
      when "rot90", "rot180", "rot270"
        angle = name == "rot90" ? "d90" : (name == "rot180" ? "d180" : "d270")
        return Operation.call("rot", [self, angle] of Value, options)
      end

      call_args = [self] of Value
      args.each { |a| call_args << a }
      Operation.call(name, call_args, options)
    end

    # Any undefined method is turned into a vips operation call with the image
    # as the first argument (mirrors ruby-vips' method_missing).
    macro method_missing(call)
      def {{call.name.id}}(*args, **kwargs) : OpResult | Nil
        call_args = [self] of Value
        args.each { |a| call_args << a.as(Value) }
        Vips::Operation.call({{call.name.stringify}}, call_args, Vips.kwargs_to_hash(kwargs))
      end
    end
  end
end
