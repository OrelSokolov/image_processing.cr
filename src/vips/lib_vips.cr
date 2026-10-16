# FFI bindings to libvips + the parts of glib/gobject that are needed to
# marshal arguments in and out of vips operations. This is the Crystal
# equivalent of the layer that the ruby-vips gem provides for the Ruby
# image_processing gem.
@[Link(ldflags: "-l:libvips.so.42")]
@[Link("glib-2.0")]
@[Link("gobject-2.0")]
lib LibVips
  type VipsImage = Void*
  type VipsOperation = Void*
  type VipsObject = Void*

  # core vips
  fun vips_init(argv0 : UInt8*) : Int32
  fun vips_version(flag : Int32) : Int32
  fun vips_shutdown : Nil
  fun vips_error_buffer : UInt8*
  fun vips_error_clear : Nil

  fun vips_foreign_find_load(filename : UInt8*) : UInt8*
  fun vips_foreign_find_save(filename : UInt8*) : UInt8*

  fun vips_operation_new(operation_name : UInt8*) : VipsOperation*
  fun vips_cache_operation_build(operation : VipsOperation*) : VipsOperation*
  fun vips_object_unref_outputs(object : VipsObject*) : Nil
  fun vips_object_get_argument(object : VipsObject*, name : UInt8*, pspec : GParamSpec**,
                               arg_class : VipsArgumentClass**, arg_instance : Void**) : Int32

  # image accessors / metadata
  fun vips_image_new_matrix_from_array(width : Int32, height : Int32, array : Float64*, n : Int32) : VipsImage*
  fun vips_image_get_width(image : VipsImage*) : Int32
  fun vips_image_get_height(image : VipsImage*) : Int32
  fun vips_image_get_bands(image : VipsImage*) : Int32
  fun vips_image_get_format(image : VipsImage*) : Int32
  fun vips_image_get_page_height(image : VipsImage*) : Int32
  fun vips_image_hasalpha(image : VipsImage*) : Int32
  fun vips_image_get_type : UInt64
  fun vips_image_get_fields(image : VipsImage*) : UInt8**
  fun vips_image_get(image : VipsImage*, name : UInt8*, value_copy : GValue*) : Int32
  fun vips_image_set(image : VipsImage*, name : UInt8*, value : GValue*) : Int32
  fun vips_image_remove(image : VipsImage*, name : UInt8*) : Int32

  # vips array/refstring/blob boxed types
  fun vips_array_double_new(array : Float64*, n : Int32) : Void*
  fun vips_array_int_new(array : Int32*, n : Int32) : Void*
  fun vips_array_double_get_type : UInt64
  fun vips_array_int_get_type : UInt64
  fun vips_array_image_new(images : VipsImage**, n : Int32) : Void*
  fun vips_array_image_get_type : UInt64
  fun vips_ref_string_new(str : UInt8*) : Void*
  fun vips_ref_string_get(str : Void*, length : Int32*) : UInt8*
  fun vips_ref_string_get_type : UInt64
  fun vips_blob_new(free_fn : Void*, data : UInt8*, length : UInt64) : Void*
  fun vips_blob_get(blob : Void*, size : UInt64*) : UInt8*
  fun vips_blob_get_type : UInt64

  # glib / gobject
  fun g_object_ref(object : Void*) : Void*
  fun g_object_unref(object : Void*) : Nil
  fun g_object_set_property(object : Void*, name : UInt8*, value : GValue*) : Nil
  fun g_object_get_property(object : Void*, name : UInt8*, value : GValue*) : Nil
  fun g_object_class_list_properties(oclass : Void*, n_pspecs : UInt32*) : GParamSpec**
  fun g_value_init(value : GValue*, g_type : UInt64) : GValue*
  fun g_value_unset(value : GValue*) : Nil
  fun g_value_set_boolean(value : GValue*, v : Int32) : Nil
  fun g_value_set_int(value : GValue*, v : Int32) : Nil
  fun g_value_set_uint(value : GValue*, v : UInt32) : Nil
  fun g_value_set_long(value : GValue*, v : Int64) : Nil
  fun g_value_set_ulong(value : GValue*, v : UInt64) : Nil
  fun g_value_set_int64(value : GValue*, v : Int64) : Nil
  fun g_value_set_uint64(value : GValue*, v : UInt64) : Nil
  fun g_value_set_float(value : GValue*, v : Float32) : Nil
  fun g_value_set_double(value : GValue*, v : Float64) : Nil
  fun g_value_set_string(value : GValue*, v : UInt8*) : Nil
  fun g_value_set_enum(value : GValue*, v : Int32) : Nil
  fun g_value_set_object(value : GValue*, v : Void*) : Nil
  fun g_value_set_boxed(value : GValue*, v : Void*) : Nil
  fun g_value_get_boolean(value : GValue*) : Int32
  fun g_value_get_int(value : GValue*) : Int32
  fun g_value_get_int64(value : GValue*) : Int64
  fun g_value_get_double(value : GValue*) : Float64
  fun g_value_get_string(value : GValue*) : UInt8*
  fun g_value_get_enum(value : GValue*) : Int32
  fun g_value_get_object(value : GValue*) : Void*
  fun g_value_get_boxed(value : GValue*) : Void*
  fun g_type_class_ref(gtype : UInt64) : Void*
  fun g_type_class_unref(klass : Void*) : Nil
  fun g_type_from_name(name : UInt8*) : UInt64
  fun g_type_fundamental(gtype : UInt64) : UInt64
  fun g_type_name(gtype : UInt64) : UInt8*
  fun g_enum_get_value_by_nick(enum_class : Void*, nick : UInt8*) : GEnumValue*
  fun g_enum_get_value(enum_class : Void*, value : Int32) : GEnumValue*
  fun g_flags_get_value_by_nick(flags_class : Void*, nick : UInt8*) : GEnumValue*
  fun g_value_set_flags(value : GValue*, v : Int32) : Nil
  fun g_strfreev(str_array : UInt8**) : Nil
  fun g_free(mem : Void*) : Nil

  struct GValue
    g_type : UInt64
    data : UInt64[2]
  end

  struct GParamSpec
    g_type_instance : Void*   # GTypeInstance
    name : UInt8*
    flags : UInt32            # GParamFlags
    value_type : UInt64       # GType
    owner_type : UInt64       # GType
  end

  struct GEnumValue
    value : Int32
    value_name : UInt8*
    value_nick : UInt8*
  end

  # struct VipsArgument { GParamSpec *pspec; }
  # struct VipsArgumentClass {
  #   VipsArgument parent;
  #   VipsObjectClass *object_class;
  #   VipsArgumentFlags flags;
  #   int priority;
  #   guint offset;
  # };
  struct VipsArgumentClass
    pspec : GParamSpec*
    object_class : Void*
    flags : Int32
    priority : Int32
    offset : UInt32
  end
end
