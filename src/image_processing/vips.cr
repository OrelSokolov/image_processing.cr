module ImageProcessing
  module Vips
    raise "image_processing/vips requires libvips 8.6+" unless ::Vips.at_least_libvips?(8, 6)

    # Returns whether the given image file is processable.
    def self.valid_image?(file) : Bool
      path = file.responds_to?(:path) ? file.path : file.to_s
      image = ::Vips::Image.new_from_file(path, access: :sequential)
      image.avg
      true
    rescue ::Vips::Error
      false
    end

    class Processor < ::ImageProcessing::Processor(::Vips::Image)
      # Default sharpening mask that provides a fast and mild sharpen.
      SHARPEN_MASK = ::Vips::Image.new_from_array(
        [[-1, -1, -1],
         [-1, 32, -1],
         [-1, -1, -1]], 24)

      # Loads the image on disk into a Vips::Image object. Accepts additional
      # loader-specific options (e.g. interlacing). Afterwards auto-rotates
      # the image to be upright.
      def self.load_image(source : BlockArg, loader : Hash(String, OptValue)) : ::Vips::Image
        options = loader.dup
        loader_name = options.delete("loader").try(&.to_s.presence)
        autorot = options.has_key?("autorot") ? ImageProcessing.truthy?(options.delete("autorot")) : true

        image =
          if source.is_a?(::Vips::Image)
            source
          else
            path = source.as(String)

            if loader_name
              ::Vips::Operation.call(
                "#{loader_name}load",
                [path] of ::Vips::Value,
                ImageProcessing.to_vips_options(options)
              ).as(::Vips::Image)
            else
              options = Utils.select_valid_loader_options(path, options)
              ::Vips::Image.new_from_file(path, ImageProcessing.to_vips_options(options))
            end
          end

        image = image.autorot if autorot && !options.has_key?("autorotate")
        image
      end

      # See #thumbnail.
      def self.supports_resize_on_load? : Bool
        true
      end

      # Writes the Vips::Image object to disk. This starts the processing
      # pipeline defined in the Vips::Image object. Accepts additional
      # saver-specific options (e.g. quality).
      def self.save_image(image : ::Vips::Image, path : String,
                          saver : Hash(String, OptValue)) : Nil
        options = saver.dup
        options["Q"] = options.delete("quality") if options.has_key?("quality")

        if saver_name = options.delete("saver").try(&.to_s.presence)
          nickname = "#{saver_name}save"
          Utils.apply_strip_compat!(nickname, options)
          ::Vips::Operation.call(
            nickname,
            [image, path] of ::Vips::Value,
            ImageProcessing.to_vips_options(options)
          )
        else
          Utils.apply_strip_compat!(nil, options, path)
          options = Utils.select_valid_saver_options(path, options)
          image.write_to_file(path, ImageProcessing.to_vips_options(options))
        end
      end

      # Resizes the image to not be larger than the specified dimensions.
      def resize_to_limit(args : Array(OptValue),
                          options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        width = args[0]?
        height = args[1]?
        w, h = default_dimensions(width, height)
        thumbnail(w, h, options.merge({"size" => "down"}))
      end

      # Resizes the image to fit within the specified dimensions.
      def resize_to_fit(args : Array(OptValue),
                        options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        width = args[0]?
        height = args[1]?
        w, h = default_dimensions(width, height)
        thumbnail(w, h, options)
      end

      # Resizes the image to fill the specified dimensions, applying any
      # necessary cropping.
      def resize_to_fill(args : Array(OptValue),
                         options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        width = args[0]?
        height = args[1]?
        opts = options.has_key?("crop") ? options : options.merge({"crop" => "centre"})
        thumbnail(width.as(Int32), height.as(Int32), opts)
      end

      # Resizes the image to fit within the specified dimensions and fills
      # the remaining area with the specified background color.
      def resize_and_pad(args : Array(OptValue),
                         options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        width = args[0]?
        height = args[1]?
        gravity = options.delete("gravity") || "centre"
        extend_value = options.delete("extend")
        background = options.delete("background")
        alpha = options.delete("alpha")

        image = thumbnail(width.as(Int32), height.as(Int32), options)
        image = image.add_alpha if alpha && !image.has_alpha?
        pad_options = {} of String => OptValue
        pad_options["extend"] = extend_value if extend_value
        pad_options["background"] = background if background
        image.gravity(gravity.to_s, width.as(Int32), height.as(Int32),
          ImageProcessing.to_vips_options(pad_options))
      end

      # Resizes the image to cover the specified dimensions, without
      # cropping the excess.
      def resize_to_cover(args : Array(OptValue),
                          options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        width = args[0]?
        height = args[1]?
        w = width.as(Int32)
        h = height.as(Int32)

        acc = image
        base = acc.is_a?(String) ? self.class.load_image(acc, {} of String => OptValue) : acc

        image_ratio = base.width.to_f64 / base.height.to_f64
        thumbnail_ratio = w.to_f64 / h.to_f64

        if image_ratio > thumbnail_ratio
          w = ::Vips::MAX_COORD
        else
          h = ::Vips::MAX_COORD
        end

        thumbnail(w, h, options.merge({"crop" => "none"}))
      end

      # Rotates the image by an arbitrary angle.
      def rotate(args : Array(OptValue),
                 options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        degrees = args[0]?
        deg = degrees.as?(Int32) || degrees.as?(Int64).try(&.to_i32) ||
              raise(Error.new("invalid degrees: #{degrees.inspect}"))

        if [90, 180, 270].includes?(deg) && options.empty?
          case deg
          when 90  then image.as(::Vips::Image).rot90
          when 180 then image.as(::Vips::Image).rot180
          else          image.as(::Vips::Image).rot270
          end
        else
          image.as(::Vips::Image).similarity(ImageProcessing.to_vips_options(
            options.merge({"angle" => deg})
          ))
        end
      end

      # Overlays the specified image over the current one. Supports specifying
      # composite mode, direction or offset of the overlay image.
      def composite(args : Array(OptValue),
                    options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        overlay = args[0]?
        mode_arg = args[1]?
        # if the mode argument is given, call the original Vips::Image#composite
        if mode_arg
          overlays = overlay.is_a?(Array) ? overlay : [overlay]
          converted = overlays.map do |object|
            convert_to_image(object, "overlay")
          end
          return image.as(::Vips::Image).composite(converted, mode_arg,
            ImageProcessing.to_vips_options(options))
        end

        options = options.dup
        mode = options.delete("mode") || "over"
        gravity = options.delete("gravity") || "north-west"
        offset = options.delete("offset")

        overlay_image = convert_to_image(overlay, "overlay")
        # add alpha channel so that #gravity can use a transparent background
        overlay_image = overlay_image.add_alpha unless overlay_image.has_alpha?

        # apply offset with correct gravity and make remainder transparent
        if offset.is_a?(Array)
          dx = offset[0].as?(Int32) || raise(Error.new("invalid offset: #{offset.inspect}"))
          dy = offset[1].as?(Int32) || raise(Error.new("invalid offset: #{offset.inspect}"))
          opposite_gravity = Utils.opposite_gravity(gravity.to_s)
          overlay_image = overlay_image.gravity(opposite_gravity,
            overlay_image.width + dx, overlay_image.height + dy)
        end

        # create image-sized transparent background and apply specified gravity
        base = image.as(::Vips::Image)
        overlay_image = overlay_image.gravity(gravity.to_s, base.width, base.height)

        # apply the composition
        base.composite(overlay_image, mode, ImageProcessing.to_vips_options(options))
      end

      # make metadata setter methods chainable
      def set(args : Array(OptValue),
              options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        img = image.as(::Vips::Image)
        img.set(args[0].to_s, ImageProcessing.to_vips_value(args[1]))
        img
      end

      def set_type(args : Array(OptValue),
                   options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        img = image.as(::Vips::Image)
        gtype = args[0].as?(Int64) || args[0].as?(Int32).try(&.to_i64) ||
                raise(Error.new("invalid GType: #{args[0].inspect}"))
        img.set_type(gtype.to_u64, args[1].to_s, args[2])
        img
      end

      def set_value(args : Array(OptValue),
                    options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        img = image.as(::Vips::Image)
        img.set_value(args[0].to_s, ImageProcessing.to_vips_value(args[1]))
        img
      end

      def remove(args : Array(OptValue),
                 options : Hash(String, OptValue) = {} of String => OptValue) : ::Vips::Image
        img = image.as(::Vips::Image)
        img.remove(args[0].to_s)
        img
      end

      private def thumbnail(width : Int32, height : Int32,
                            options : Hash(String, OptValue)) : ::Vips::Image
        options = options.dup
        sharpen = options.has_key?("sharpen") ? options.delete("sharpen") : SHARPEN_MASK

        acc = image
        image =
          if acc.is_a?(String) # path: resize on load
            ::Vips::Image.thumbnail(acc, width, height,
              ImageProcessing.to_vips_options(options))
          else
            # we're already calling Image#autorot when loading the image
            opts = options.merge({"no_rotate" => true})
            acc.as(::Vips::Image).thumbnail_image(width, height,
              ImageProcessing.to_vips_options(opts))
          end

        if sharpen
          mask = sharpen.as(::Vips::Image)
            image = image.conv(mask, precision: :integer)
        end
        image
      end

      # Hack to allow omitting one dimension.
      private def default_dimensions(width : OptValue, height : OptValue) : {Int32, Int32}
        raise Error.new("either width or height must be specified") unless width || height

        {(width || ::Vips::MAX_COORD).as(Int32), (height || ::Vips::MAX_COORD).as(Int32)}
      end

      # Converts the image on disk in various forms into a Vips::Image object.
      private def convert_to_image(object : OptValue, name : String) : ::Vips::Image
        case object
        when ::Vips::Image then object
        when String        then ::Vips::Image.new_from_file(object)
        when Path          then ::Vips::Image.new_from_file(object.to_s)
        when File, Tempfile then ::Vips::Image.new_from_file(object.path)
        else
          raise ArgumentError.new("#{name} must be a Vips::Image, String, Pathname, or respond to #path")
        end
      end

      module Utils
        # libvips uses various loaders depending on the input format.
        def self.select_valid_loader_options(source_path : String,
                                             options : Hash(String, OptValue)) : Hash(String, OptValue)
          loader = ::Vips.foreign_find_load(source_path)
          loader ? select_valid_options(loader, options) : options
        end

        # Filters out unknown options for saving images.
        def self.select_valid_saver_options(destination_path : String,
                                            options : Hash(String, OptValue)) : Hash(String, OptValue)
          saver = ::Vips.foreign_find_save(destination_path)
          saver ? select_valid_options(saver, options) : options
        end

        # libvips uses various loaders and savers depending on the input and
        # output image format. Each of these loaders and savers accept slightly
        # different options, so to allow the user to be able to specify options
        # for a specific loader/saver and have it ignored for other
        # loaders/savers, we do some introspection and filter out options that
        # don't exist for a particular loader or saver.
        def self.select_valid_options(operation_name : String,
                                      options : Hash(String, OptValue)) : Hash(String, OptValue)
          introspection = ::Vips::Introspect.get(operation_name)

          options.select do |name, _|
            introspection.canonical_option_name?(name)
          end
        end

        def self.opposite_gravity(gravity : String) : String
          gravity.split("-").map do |word|
            case word
            when "north" then "south"
            when "south" then "north"
            when "east"  then "west"
            when "west"  then "east"
            else word
            end
          end.join("-")
        end

        # libvips 8.15 replaced the saver's "strip" boolean with the "keep"
        # flags (empty = keep nothing). Translate the legacy option when the
        # loaded libvips only knows the new one.
        def self.apply_strip_compat!(saver_name : String?, options : Hash(String, OptValue),
                                     path : String? = nil) : Nil
          return unless options.has_key?("strip")

          nickname = saver_name || ::Vips.foreign_find_save(path.not_nil!)
          return unless nickname

          introspection = ::Vips::Introspect.get(nickname)
          return if introspection.canonical_option_name?("strip")

          if introspection.canonical_option_name?("keep")
            stripped = ImageProcessing.truthy?(options.delete("strip"))
            options["keep"] = 0 if stripped # VIPS_FOREIGN_KEEP_NONE
          end
        end
      end
    end

    extend Chainable(Processor, ::Vips::Image)
    ChainableMacros.def_chainable_methods(::ImageProcessing::Vips::Processor, ::Vips::Image)
    ChainableMacros.def_module_operations({invert, shrink, rot, rot90, add_alpha, copy}, ::Vips::Image)
    ChainableMacros.def_raising_predicates({valid?})
  end
end
