# A Ruby-Tempfile-like object: created empty on disk, reopened (and rewound)
# after the processor has written to its path, and deleted at process exit.
module ImageProcessing
  class Tempfile
    getter path : String

    @io : File?

    @@registry = [] of Tempfile

    def initialize(basename : String, suffix : String = "")
      @path = File.tempname(basename, suffix)
      File.write(@path, "")
      @io = File.open(@path, "r+b")
      @@registry << self
    end

    # Refreshes the file descriptor to pick up the file contents that the
    # processor wrote and rewinds to the beginning.
    def open : self
      close
      @io = File.open(@path, "r+b")
      @io.not_nil!.seek(0)
      self
    end

    def read(length : Int? = nil) : String?
      io = @io || (return open.read(length))
      length ? io.read_string(length.not_nil!) : io.gets_to_end
    end

    def pos : Int64
      io = @io || return 0_i64
      io.pos
    end

    def size : Int64
      File.size(@path)
    end

    def exists? : Bool
      File.exists?(@path)
    end

    def close : Nil
      @io.try &.close
      @io = nil
    end

    # Closes and deletes the file.
    def close! : Nil
      close
      delete
    end

    def delete : Nil
      File.delete(@path) if File.exists?(@path)
    end

    def binmode? : Bool
      true
    end

    def inspect : String
      "#<Tempfile: #{@path}>"
    end

    at_exit do
      @@registry.each do |tempfile|
        tempfile.close
        if File.exists?(tempfile.path)
          File.delete(tempfile.path) rescue nil
        end
      end
    end
  end
end
