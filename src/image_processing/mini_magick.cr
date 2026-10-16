module ImageProcessing
  module MiniMagick
    def self.convert_shim(&block : ::MiniMagick::Tool -> Nil) : String
      ::MiniMagick.convert(&block)
    end

    def self.convert_shim : ::MiniMagick::Tool
      ::MiniMagick.convert
    end

    # Returns whether the given image file is processable.
    def self.valid_image?(file) : Bool
      path = file.responds_to?(:path) ? file.path : file.to_s
      convert = ::MiniMagick.convert
      convert << path
      convert << "null:"
      convert.call
      true
    rescue ::MiniMagick::Error
      false
    end

    class Processor < ::ImageProcessing::Processor(::MiniMagick::Tool)
      # Default sharpening parameters used on generated thumbnails.
      SHARPEN_PARAMETERS = {"radius" => 0, "sigma" => 1}

      # Initializes the image on disk into a MiniMagick::Tool object. Accepts
      # additional options related to loading the image (e.g. geometry).
      # Additionally auto-orients the image to be upright.
      def self.load_image(source : BlockArg, loader : Hash(String, OptValue)) : ::MiniMagick::Tool
        options = loader.dup

        loader_name = options.delete("loader").try(&.to_s.presence)
        page = options.delete("page")
        geometry = options.delete("geometry")
        auto_orient = options.has_key?("auto_orient") ? ImageProcessing.truthy?(options.delete("auto_orient")) : true

        magick =
          if source.is_a?(::MiniMagick::Tool)
            source
          else
            path = source.as(String)
            tool = ::MiniMagick.convert

            Utils.apply_options(tool, options)

            input = path
            input = "#{loader_name}:#{input}" if loader_name
            input += "[#{page}]" if page
            input += "[#{geometry}]" if geometry

            tool << input
            tool
          end

        magick.auto_orient if auto_orient
        magick
      end

      # Calls the built ImageMagick command to perform processing and save
      # the result to disk. Accepts additional options related to saving the
      # image (e.g. quality).
      def self.save_image(magick : ::MiniMagick::Tool, destination_path : String,
                          saver : Hash(String, OptValue)) : Nil
        options = saver.dup
        allow_splitting = options.has_key?("allow_splitting") && ImageProcessing.truthy?(options.delete("allow_splitting"))

        Utils.apply_options(magick, options)

        magick << destination_path
        magick.call

        Utils.disallow_split_layers!(destination_path) unless allow_splitting
      end

      # Resizes the image to not be larger than the specified dimensions.
      def resize_to_limit(args : Array(OptValue),
                          options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        width = args[0]?
        height = args[1]?
        thumbnail(["#{width}x#{height}>"] of OptValue, options)
      end

      # Resizes the image to fit within the specified dimensions.
      def resize_to_fit(args : Array(OptValue),
                        options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        width = args[0]?
        height = args[1]?
        thumbnail(["#{width}x#{height}"] of OptValue, options)
      end

      # Resizes the image to fill the specified dimensions, applying any
      # necessary cropping.
      def resize_to_fill(args : Array(OptValue),
                         options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        width = args[0]?
        height = args[1]?
        gravity = options.delete("gravity") || "Center"

        thumbnail(["#{width}x#{height}^"] of OptValue, options)
        magick.as(::MiniMagick::Tool).gravity(gravity.to_s)
        magick.as(::MiniMagick::Tool).background(color(:transparent))
        magick.as(::MiniMagick::Tool).extent("#{width}x#{height}")
        magick.as(::MiniMagick::Tool)
      end

      # Resizes the image to fit within the specified dimensions and fills
      # the remaining area with the specified background color.
      def resize_and_pad(args : Array(OptValue),
                         options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        width = args[0]?
        height = args[1]?
        background = options.has_key?("background") ? options.delete("background") : :transparent
        gravity = options.delete("gravity") || "Center"

        thumbnail(["#{width}x#{height}"] of OptValue, options)
        tool = magick.as(::MiniMagick::Tool)
        tool.background(color(background))
        tool.gravity(gravity.to_s)
        tool.extent("#{width}x#{height}")
        tool
      end

      # Resizes the image to cover the specified dimensions, without
      # cropping the excess.
      def resize_to_cover(args : Array(OptValue),
                          options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        width = args[0]?
        height = args[1]?
        thumbnail(["#{width}x#{height}^"] of OptValue, options)
      end

      # Crops the image with the specified crop points.
      def crop(args : Array(OptValue),
               options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        tool = magick.as(::MiniMagick::Tool)
        case args.size
        when 1
          tool.crop(args[0].to_s)
        when 4
          tool.crop("#{args[2]}x#{args[3]}+#{args[0]}+#{args[1]}")
        else
          raise ArgumentError.new("wrong number of arguments (expected 1 or 4, got #{args.size})")
        end
        tool
      end

      # Rotates the image by an arbitrary angle. For angles that are not
      # multiple of 90 degrees an optional background color can be specified
      # to fill in the gaps.
      def rotate(args : Array(OptValue),
                 options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        degrees = args[0]?
        tool = magick.as(::MiniMagick::Tool)
        tool.background(color(options["background"])) if options.has_key?("background")
        tool.rotate(degrees.to_s)
        tool
      end

      # Overlays the specified image over the current one. Supports specifying
      # an additional mask, composite mode, direction or offset of the overlay
      # image.
      def composite(args : Array(OptValue),
                    options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        perform_composite(args, options) { |tool| tool }
      end

      def composite_with_block(args : Array(OptValue),
                               options : Hash(String, OptValue),
                               &block : Proc(::MiniMagick::Tool, ::MiniMagick::Tool | Nil)) : ::MiniMagick::Tool
        perform_composite(args, options, &block)
      end

      # :nodoc: dispatch target from the base processor
      private def composite_dispatch(block, args, options) : BlockArg
        composite_with_block(args, options) do |tool|
          block.not_nil!.call(tool)
          nil
        end
      end

      # Defines settings from the provided hash or string.
      def define(args : Array(OptValue),
                 call_options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        tool = magick.as(::MiniMagick::Tool)
        define_options = args[0]?
        case define_options
        when String
          tool.option("define", [define_options.to_s])
        when Hash
          Utils.apply_define(tool, define_options.as(Hash(String, OptValue)))
        else
          raise ArgumentError.new("invalid define options: #{define_options.inspect}")
        end
        tool
      end

      # Specifies resource limits from the provided hash.
      def limits(args : Array(OptValue),
                 call_options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        tool = magick.as(::MiniMagick::Tool)
        options = args[0]?.as(Hash(String, OptValue))
        options.each do |type, value|
          tool.args.unshift("-limit", type.to_s, value.to_s)
        end
        tool
      end

      # Appends a raw ImageMagick command-line argument to the command.
      def append(args : Array(OptValue),
                 options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        tool = magick.as(::MiniMagick::Tool)
        if args.empty?
          tool.option("append")
        else
          tool.merge!(args.map(&.to_s))
        end
        tool
      end

      private def perform_composite(args : Array(OptValue),
                                    options : Hash(String, OptValue),
                                    &block : Proc(::MiniMagick::Tool, ::MiniMagick::Tool | Nil)) : ::MiniMagick::Tool
        tool = magick.as(::MiniMagick::Tool)
        overlay = args.empty? ? :none : args[0]?
        return tool.option("composite") if overlay == :none

        options = options.dup

        if options.has_key?("compose")
          STDERR.puts "[IMAGE_PROCESSING] The :compose parameter in #composite has been renamed to :mode, the :compose alias will be removed in ImageProcessing 2."
          options["mode"] = options.delete("compose")
        end

        geometry = nil
        if options.has_key?("geometry")
          STDERR.puts "[IMAGE_PROCESSING] The :geometry parameter in #composite has been deprecated and will be removed in ImageProcessing 2. Use :offset instead, e.g. `geometry: \"+10+15\"` should be replaced with `offset: [10, 15]`."
          geometry = options.delete("geometry").to_s
        end

        mode = options.delete("mode")
        mask = options.delete("mask")
        gravity = options.delete("gravity")
        offset = options.delete("offset")
        args = options.delete("args")

        geometry = format_offset(offset) if offset

        overlay_path = convert_to_path(overlay, "overlay")
        mask_path = mask ? convert_to_path(mask.not_nil!, "mask") : nil

        tool << overlay_path
        tool << mask_path if mask_path

        tool.compose(mode.to_s) if mode
        if args
          compose_settings = {} of String => OptValue
          compose_settings["args"] = args
          define_options = {} of String => OptValue
          define_options["compose"] = compose_settings
          define([define_options] of OptValue)
        end

        tool.gravity(gravity.to_s) if gravity
        tool.geometry(geometry) if geometry

        result = block.call(tool)
        result.nil? ? tool : result

        tool.option("composite")
      end

      private def format_offset(offset : OptValue) : String
        dx = offset.as(Array)[0].as?(Int32) || raise(Error.new("invalid offset: #{offset.inspect}"))
        dy = offset.as(Array)[1].as?(Int32) || raise(Error.new("invalid offset: #{offset.inspect}"))
        "#{dx >= 0 ? "+#{dx}" : dx}#{dy >= 0 ? "+#{dy}" : dy}"
      end

      # Converts the given color value into an identifier ImageMagick
      # understands. This supports specifying RGB(A) values with arrays, which
      # mainly exists for compatibility with the libvips implementation.
      private def color(value : OptValue) : String
        return "rgba(255,255,255,0.0)" if value.to_s == "transparent"
        return "rgb(#{value.as(Array).map(&.to_s).join(",")})" if value.is_a?(Array) && value.as(Array).size == 3
        return "rgba(#{value.as(Array).map(&.to_s).join(",")})" if value.is_a?(Array) && value.as(Array).size == 4
        return value.to_s if value.is_a?(String)

        raise ArgumentError.new("unrecognized color format: #{value.inspect} (must be one of: string, 3-element RGB array, 4-element RGBA array)")
      end

      # Resizes the image using the specified geometry, and sharpens the
      # resulting thumbnail. Private, like in the Ruby version: a public
      # "thumbnail" operation maps to ImageMagick's "-thumbnail" instead.
      private def thumbnail(args : Array(OptValue),
                    options : Hash(String, OptValue) = {} of String => OptValue) : ::MiniMagick::Tool
        geometry = args[0].to_s
        options = options.dup
        options = options.dup
        sharpen = options.delete("sharpen")

        tool = magick.as(::MiniMagick::Tool)
        tool.resize(geometry)

        if sharpen
          params = {"radius" => 0, "sigma" => 1}
          if sharpen.is_a?(Hash)
            sharpen.as(Hash(String, OptValue)).each do |key, value|
              params = params.merge({key.to_s => value})
            end
          end
          tool.sharpen("#{params["radius"]}x#{params["sigma"]}")
        end

        tool
      end

      # Converts the image on disk in various forms into a path.
      private def convert_to_path(file : OptValue, name : String) : String
        case file
        when String        then file
        when Path          then file.to_s
        when File, Tempfile then file.path
        else
          raise ArgumentError.new("#{name} must be a String, Pathname, or respond to #path")
        end
      end

      module Utils
        # When a multi-layer format is being converted into a single-layer
        # format, ImageMagick will create multiple images, one for each layer.
        # We want to warn the user that this is probably not what they wanted.
        def self.disallow_split_layers!(destination_path : String) : Nil
          base = destination_path.sub(/(\.\w+)?$/, "")
          layers = Dir.glob("#{base}-*")

          unless layers.empty?
            layers.each { |path| File.delete(path) }
            raise Error.new("Source format is multi-layer, but destination format is single-layer. If you care only about the first layer, add `.loader(page: 0)` to your pipeline. If you want to process each layer, see https://github.com/janko/image_processing/wiki/Splitting-a-PDF-into-multiple-images or use `.saver(allow_splitting: true)`.")
          end
        end

        # Applies options from the provided hash.
        def self.apply_options(magick : ::MiniMagick::Tool,
                               options : Hash(String, OptValue)) : Nil
          options = options.dup
          define = options.has_key?("define") ? options.delete("define").as?(Hash(String, OptValue)) || {} of String => OptValue : {} of String => OptValue

          options.each do |option, value|
            case value
            when true, nil
              magick.option(option)
            when false
              # mini_magick's behavior: `magick.send(option).+` appends "-option"
              # and turns it into "+option" with no further values.
              magick.option(option).plus
            when Array
              magick.option(option, value.map(&.to_s))
            else
              magick.option(option, [value.to_s])
            end
          end

          apply_define(magick, define)
        end

        # Applies settings from the provided (nested) hash.
        def self.apply_define(magick : ::MiniMagick::Tool,
                              options : Hash(String, OptValue)) : ::MiniMagick::Tool
          options.each do |namespace, settings|
            namespace = namespace.to_s.tr("_", "-")

            settings.as(Hash(String, OptValue)).each do |key, value|
              key = key.to_s.tr("_", "-")

              magick.option("define", ["#{namespace}:#{key}=#{value}"])
            end
          end

          magick
        end
      end
    end

    extend Chainable(Processor, ::MiniMagick::Tool)
    ChainableMacros.def_chainable_methods(::ImageProcessing::MiniMagick::Processor, ::MiniMagick::Tool)
    ChainableMacros.def_module_operations({flip, thumbnail}, ::MiniMagick::Tool)
    ChainableMacros.def_raising_predicates({valid?})
  end
end
