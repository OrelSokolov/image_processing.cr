module ImageProcessing
  class Pipeline(P, Acc)
    DEFAULT_FORMAT = "jpg"

    getter loader : Hash(String, OptValue)
    getter saver : Hash(String, OptValue)
    getter format : String?
    getter operations : Array(Operation)
    getter destination : String?
    def processor : P.class
      P
    end

    # Initializes the pipeline with all the processing options.
    def initialize(@options : Options)
      unless @options.source
        raise Error.new("source file is not provided")
      end

      @loader = @options.loader
      @saver = @options.saver
      @format = @options.format
      @operations = @options.operations
      @destination = @options.destination
      @processor = P
    end

    # Determines the destination and calls the processor.
    def call(save : Bool = true) : Tempfile | Acc | Nil
      if save == false
        call_processor.as(Tempfile | Acc)
      elsif dest = @destination
        handle_destination do
          call_processor(destination: dest)
          nil
        end
      else
        create_tempfile do |tempfile|
          call_processor(destination: tempfile.path)
        end
      end
    end

    # Retrieves the source path on disk.
    def source_path : String?
      src = source
      src.is_a?(String) ? src : nil
    end

    # Determines the appropriate destination image format.
    def destination_format : String
      format = determine_format(@destination) if @destination
      format ||= @format
      format ||= determine_format(source_path) if source_path

      format || DEFAULT_FORMAT
    end

    private def call_processor(destination : String? = nil)
      P.call(
        source: source,
        loader: @loader,
        operations: @operations,
        saver: @saver,
        destination: destination
      )
    end

    # Creates a new tempfile for the destination file, yields it, and refreshes
    # the file descriptor to get the updated file.
    private def create_tempfile(& : Tempfile -> Nil) : Tempfile
      tempfile = Tempfile.new("image_processing", ".#{destination_format}")

      begin
        yield tempfile
      rescue e
        tempfile.close!
        raise e
      end

      tempfile.open
      tempfile
    end

    # In case of processing errors, both libvips and imagemagick will leave the
    # empty destination file they created, so this method makes sure it is
    # deleted in case an exception is raised on saving the image.
    private def handle_destination(& : -> Nil)
      destination_existed = File.exists?(@destination.not_nil!)
      yield
    rescue e
      dest = @destination.not_nil!
      File.delete(dest) if File.exists?(dest) && !destination_existed
      raise e
    end

    # Converts the source image object into a path or the accumulator object.
    private def source : String | Acc
      src = @options.source
      case src
      when String               then src
      when File                 then src.path
      when Tempfile             then src.path
      when Path                 then src.to_s
      when Acc                  then src
      else
        raise Error.new("invalid source: #{src.inspect}")
      end
    end

    private def determine_format(file_path : String?) : String?
      return nil unless file_path

      extension = File.extname(file_path)

      extension[1..]? if extension.size > 1
    end
  end
end
