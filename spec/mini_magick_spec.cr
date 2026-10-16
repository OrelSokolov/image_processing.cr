require "./spec_helper"

describe ImageProcessing::MiniMagick do
  portrait = fixture_image("portrait.jpg")
  landscape = fixture_image("landscape.jpg")
  square = fixture_image("square.jpg")

  it "applies imagemagick operations" do
    actual = ImageProcessing::MiniMagick.flip.call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Tempfile.new("result", ".jpg")
    MiniMagick.convert do |cmd|
      cmd << portrait.path
      cmd.flip
      cmd << expected.path
    end

    assert_similar expected.path, actual.path
  end

  it "applies thumbnail operation" do
    magick = ImageProcessing::MiniMagick.thumbnail("400x400").call(portrait, save: false).as(MiniMagick::Tool)
    magick.args.should contain("-thumbnail")
  end

  it "applies operations named as Object methods" do
    magick = ImageProcessing::MiniMagick.custom { |image| image.as(MiniMagick::Tool).clone }.call(portrait, save: false).as(MiniMagick::Tool)
    magick.args.should contain("-clone")
  end

  it "applies macro operations" do
    actual = ImageProcessing::MiniMagick.resize_to_limit(400, 400).call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Tempfile.new("result", ".jpg")
    MiniMagick.convert do |cmd|
      cmd << portrait.path
      cmd.resize("400x400")
      cmd << expected.path
    end

    assert_similar expected.path, actual.path
  end

  it "applies format" do
    result = ImageProcessing::MiniMagick.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    File.extname(result.path).should eq(".png")
    assert_type "PNG", result
  end

  it "accepts page" do
    tiff = ImageProcessing::Tempfile.new("file", ".tiff")
    MiniMagick.convert do |convert|
      convert.merge!([portrait.path, portrait.path, portrait.path])
      convert << tiff.path
    end

    processed = ImageProcessing::MiniMagick
      .source(tiff)
      .loader(page: 0)
      .convert!("jpg")
      .as(ImageProcessing::Tempfile)

    processed.size.should_not eq(0)
  end

  it "disallows split layers by default" do
    tiff = ImageProcessing::Tempfile.new("file", ".tiff")
    MiniMagick.convert do |convert|
      convert.merge!([portrait.path, portrait.path, portrait.path])
      convert << tiff.path
    end

    pipeline = ImageProcessing::MiniMagick.source(tiff).convert("jpg")

    expect_raises(ImageProcessing::Error) { pipeline.call }

    tempfile = pipeline.saver(allow_splitting: true).call.as(ImageProcessing::Tempfile)
    tempfile.size.should eq(0)
    Dir.glob(tempfile.path.sub(/\.\w+$/, "-*")).each do |path|
      File.size(path).should_not eq(0)
      File.delete(path)
    end
  end

  it "allows resizing images without extension" do
    result1 = ImageProcessing::Tempfile.new("image", "") # no file extension

    ImageProcessing::MiniMagick
      .source(portrait)
      .resize_to_limit(400, 400)
      .call(destination: result1.path)

    result2 = ImageProcessing::MiniMagick
      .source(portrait)
      .resize_to_limit!(400, 400)
      .as(ImageProcessing::Tempfile)

    assert_similar result2.path, result1.path
  end

  it "accepts geometry" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)
    assert_dimensions [300, 400], pipeline.loader(geometry: "400x400").call
  end

  it "auto orients by default" do
    result = ImageProcessing::MiniMagick.call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result

    result = ImageProcessing::MiniMagick.loader(auto_orient: false).call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [800, 600], result
  end

  it "applies loader options" do
    result = ImageProcessing::MiniMagick.loader(loader: "jpg").call(portrait).as(ImageProcessing::Tempfile)
    assert_type "JPEG", result

    result = ImageProcessing::MiniMagick.loader(define: {"jpeg" => {"size" => "100x100"}}).call(portrait).as(ImageProcessing::Tempfile)
    # DCT scale selection varies across ImageMagick builds: IM 7.1.2-3
    # decodes jpegs:size=100x100 to 150x200 (verified against Ruby
    # image_processing on the same machine); other builds pick 75x100.
    assert_dimensions [150, 200], result

    result = ImageProcessing::MiniMagick.loader(strip: true).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.loader(strip: nil).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.loader(strip: false).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.loader(colorspace: "Gray").call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).colorspace.should eq("Gray")

    result = ImageProcessing::MiniMagick.loader(set: ["comment", "This is a comment"]).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).comment.should eq("This is a comment")
  end

  it "applies saver options" do
    result = ImageProcessing::MiniMagick.saver(define: {"jpeg" => {"fancy_upsampling" => "off", "extent" => "20KB"}}).call(portrait).as(ImageProcessing::Tempfile)
    result.size.should be < 20*1024

    result = ImageProcessing::MiniMagick.saver(strip: true).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.saver(strip: nil).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.saver(strip: false).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).exif.empty?.should be_true

    result = ImageProcessing::MiniMagick.saver(colorspace: "Gray").call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).colorspace.should eq("Gray")

    result = ImageProcessing::MiniMagick.saver(set: ["comment", "This is a comment"]).call(portrait).as(ImageProcessing::Tempfile)
    MiniMagick::Image.new(result.path).comment.should eq("This is a comment")
  end

  it "applies blocks to operations" do
    magick = ImageProcessing::MiniMagick
      .source(portrait)
      .stack { |stack| stack.as(MiniMagick::Tool).foo("bar") }
      .call(save: false)
      .as(MiniMagick::Tool)

    magick.args.should eq([portrait.path, "-auto-orient", "(", "-foo", "bar", ")"])
  end

  it "accepts magick object as source" do
    magick = MiniMagick.convert
    magick << fixture_path("rotated.jpg")
    result = ImageProcessing::MiniMagick.source(magick).call.as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result
  end

  describe ".valid_image?" do
    it "returns true for correct images" do
      ImageProcessing::MiniMagick.valid_image?(portrait).should be_true
      ImageProcessing::MiniMagick.valid_image?(copy_to_tempfile(portrait)).should be_true # no extension
    end

    it "returns false for invalid images" do
      ImageProcessing::MiniMagick.valid_image?(fixture_image("invalid.jpg")).should be_false
      ImageProcessing::MiniMagick.valid_image?(copy_to_tempfile(fixture_image("invalid.jpg"))).should be_false # no extension
    end
  end

  describe "#resize_to_limit" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "shrinks image to fit the specified dimensions" do
      assert_dimensions [300, 400], pipeline.resize_to_limit!(400, 400)
    end

    it "doesn't enlarge image if it's smaller than specified dimensions" do
      assert_dimensions [600, 800], pipeline.resize_to_limit!(1000, 1000)
    end

    it "doesn't require both dimensions" do
      assert_dimensions [300, 400], pipeline.resize_to_limit!(300, nil)
      assert_dimensions [600, 800], pipeline.resize_to_limit!(800, nil)

      assert_dimensions [300, 400], pipeline.resize_to_limit!(nil, 400)
      assert_dimensions [600, 800], pipeline.resize_to_limit!(nil, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("limit.jpg")
      assert_similar expected.path, pipeline.resize_to_limit!(400, 400).as(ImageProcessing::Tempfile).path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_limit!(400, 400, sharpen: {"sigma" => 1}).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_limit!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end
  end

  describe "#resize_to_fit" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "shrinks image to fit specified dimensions" do
      assert_dimensions [300, 400], pipeline.resize_to_fit!(400, 400)
    end

    it "enlarges image if it's smaller than given dimensions" do
      assert_dimensions [750, 1000], pipeline.resize_to_fit!(1000, 1000)
    end

    it "doesn't require both dimensions" do
      assert_dimensions [300, 400], pipeline.resize_to_fit!(300, nil)
      assert_dimensions [750, 1000], pipeline.resize_to_fit!(750, nil)

      assert_dimensions [300, 400], pipeline.resize_to_fit!(nil, 400)
      assert_dimensions [750, 1000], pipeline.resize_to_fit!(nil, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("fit.jpg")
      assert_similar expected.path, pipeline.resize_to_fit!(400, 400).as(ImageProcessing::Tempfile).path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_fit!(400, 400, sharpen: {"sigma" => 1}).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_fit!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end
  end

  describe "#resize_to_fill" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "resizes and crops the image to fill out the given dimensions" do
      assert_dimensions [400, 400], pipeline.resize_to_fill!(400, 400)
    end

    it "enlarges image and crops it if it's smaller than given dimensions" do
      assert_dimensions [1000, 1000], pipeline.resize_to_fill!(1000, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("fill.jpg")
      assert_similar expected.path, pipeline.resize_to_fill!(400, 400).as(ImageProcessing::Tempfile).path
    end

    it "accepts gravity" do
      centre = pipeline.resize_to_fill!(400, 400).as(ImageProcessing::Tempfile)
      northwest = pipeline.resize_to_fill!(400, 400, gravity: "NorthWest").as(ImageProcessing::Tempfile)
      refute_similar centre.path, northwest.path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_fill!(400, 400, sharpen: {"sigma" => 1}).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_fill!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end
  end

  describe "#resize_and_pad" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "resizes and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [400, 400], pipeline.resize_and_pad!(400, 400)
    end

    it "enlarges image and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [1000, 1000], pipeline.resize_and_pad!(1000, 1000)
    end

    it "produces correct image" do
      expected = fixture_path("pad.png")
      result = pipeline.convert("png").resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      assert_similar expected, result.path

      png = pipeline.convert!("png").as(ImageProcessing::Tempfile)
      result = pipeline.source(png).resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      assert_similar expected, result.path
    end

    it "produces correct image when enlarging" do
      pipeline = ImageProcessing::MiniMagick.source(landscape)
      expected = fixture_image("pad-large.jpg")
      assert_similar expected.path, pipeline.resize_and_pad!(1000, 1000, background: "green").as(ImageProcessing::Tempfile).path
    end

    it "accepts gravity" do
      centre = pipeline.resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      northwest = pipeline.resize_and_pad!(400, 400, gravity: "NorthWest").as(ImageProcessing::Tempfile)
      refute_similar centre.path, northwest.path
    end

    it "accepts background color" do
      variants = [
        pipeline.resize_and_pad!(400, 400, background: [0, 255, 127]).as(ImageProcessing::Tempfile),
        pipeline.resize_and_pad!(400, 400, background: [0, 255, 127, 1.0]).as(ImageProcessing::Tempfile),
        pipeline.resize_and_pad!(400, 400, background: "SpringGreen").as(ImageProcessing::Tempfile),
      ]

        variants.each_with_index do |image1, i|
      variants.each_with_index do |image2, j|
          assert_similar image1.path, image2.path if i < j
        end
      end
    end

    it "raises ArgumentError on invalid :background values" do
      expect_raises(ArgumentError) { pipeline.resize_and_pad!(400, 400, background: [0, 0]) }
      expect_raises(ArgumentError) { pipeline.resize_and_pad!(400, 400, background: [1, 1, 1, 1, 1]) }
      expect_raises(ArgumentError) { pipeline.resize_and_pad!(400, 400, background: 1) }
    end

    it "defaults background color to transparent" do
      transparent = pipeline.resize_and_pad!(400, 400, background: :transparent).as(ImageProcessing::Tempfile)
      default = pipeline.resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      assert_similar transparent.path, default.path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_and_pad!(400, 400, sharpen: {"sigma" => 1}).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_and_pad!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end
  end

  describe "#resize_to_cover" do
    portrait_pipeline = ImageProcessing::MiniMagick.source(portrait)
    landscape_pipeline = ImageProcessing::MiniMagick.source(landscape)
    square_pipeline = ImageProcessing::MiniMagick.source(square)

    it "resizes the portrait image to fill out the given landscape dimensions" do
      assert_dimensions [300, 400], portrait_pipeline.resize_to_cover!(300, 200)
    end

    it "resizes the portrait image to fill out the given portrait dimensions" do
      assert_dimensions [225, 300], portrait_pipeline.resize_to_cover!(200, 300)
    end

    it "resizes the portrait image to fill out the given square dimensions" do
      assert_dimensions [300, 400], portrait_pipeline.resize_to_cover!(300, 300)
    end

    it "resizes the landscape image to fill out the given portrait dimensions" do
      assert_dimensions [400, 300], landscape_pipeline.resize_to_cover!(200, 300)
    end

    it "resizes the landscape image to fill out the given landscape dimensions" do
      assert_dimensions [300, 225], landscape_pipeline.resize_to_cover!(300, 200)
    end

    it "resizes the landscape image to fill out the given square dimensions" do
      assert_dimensions [400, 300], landscape_pipeline.resize_to_cover!(300, 300)
    end

    it "resizes the square image to fill out the given portrait dimensions" do
      assert_dimensions [300, 300], square_pipeline.resize_to_cover!(200, 300)
    end

    it "resizes the square image to fill out the given landscape dimensions" do
      assert_dimensions [300, 300], square_pipeline.resize_to_cover!(300, 200)
    end

    it "resizes the square image to fill out the given square dimensions" do
      assert_dimensions [300, 300], square_pipeline.resize_to_cover!(300, 300)
    end

    it "produces correct image" do
      expected = fixture_image("cover.jpg")
      assert_similar expected.path, portrait_pipeline.resize_to_cover!(300, 200).as(ImageProcessing::Tempfile).path
    end

    it "accepts sharpening options" do
      sharpened = portrait_pipeline.resize_to_cover!(400, 400, sharpen: {"sigma" => 1}).as(ImageProcessing::Tempfile)
      normal = portrait_pipeline.resize_to_cover!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end
  end

  describe "#crop" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "accepts geometry argument" do
      assert_dimensions [300, 300], pipeline.crop!("300x300+0+0")
    end

    it "accepts top, left, width, height arguments" do
      assert_dimensions [300, 300], pipeline.crop!(0, 0, 300, 300)
    end
  end

  describe "#rotate" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "rotates the image by specified number of degrees" do
      assert_dimensions [600, 800], pipeline.rotate!(0)
      assert_dimensions [800, 600], pipeline.rotate!(90)
      assert_dimensions [600, 800], pipeline.rotate!("180")
      assert_dimensions [800, 600], pipeline.rotate!(-90)
    end

    it "accepts background color" do
      variants = [
        pipeline.rotate!(45, background: [0, 255, 127]).as(ImageProcessing::Tempfile),
        pipeline.rotate!(45, background: [0, 255, 127, 1.0]).as(ImageProcessing::Tempfile),
        pipeline.rotate!(45, background: "SpringGreen").as(ImageProcessing::Tempfile),
      ]

        variants.each_with_index do |image1, i|
      variants.each_with_index do |image2, j|
          assert_similar image1.path, image2.path if i < j
        end
      end
    end

    it "raises ArgumentError on invalid :background values" do
      expect_raises(ArgumentError) { pipeline.rotate!(45, background: [0, 0]) }
      expect_raises(ArgumentError) { pipeline.rotate!(45, background: [1, 1, 1, 1, 1]) }
      expect_raises(ArgumentError) { pipeline.rotate!(45, background: 1) }
    end

    it "accepts transparent background color" do
      transparent = pipeline.rotate!(45, background: :transparent).as(ImageProcessing::Tempfile)
      default = pipeline.rotate!(45, background: "rgba(255,255,255,0.0)").as(ImageProcessing::Tempfile)
      assert_similar transparent.path, default.path
    end
  end

  describe "#composite" do
    pipeline = ImageProcessing::MiniMagick.source(portrait)

    it "generates the correct composite command" do
      result = pipeline.composite!(landscape, mode: :over, gravity: "north-west", offset: [0, 0]).as(ImageProcessing::Tempfile)
      assert_similar fixture_path("composited.jpg"), result.path
    end

    it "accepts String, Path and #path object for overlay" do
      magick = pipeline.composite(landscape).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(landscape.path)

      magick = pipeline.composite(landscape.path).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(landscape.path)

      magick = pipeline.composite(Path.new(landscape.path)).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(landscape.path)

      expect_raises(ArgumentError) { pipeline.composite!(nil) }
    end

    it "accepts String, Path and #path object for mask" do
      magick = pipeline.composite(landscape, mask: landscape).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(portrait.path)

      magick = pipeline.composite(landscape, mask: landscape.path).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(landscape.path)

      magick = pipeline.composite(landscape, mask: Path.new(landscape.path)).call(save: false).as(MiniMagick::Tool)
      magick.args.should contain(landscape.path)

      expect_raises(ArgumentError) { pipeline.composite!(landscape, mask: true) }
    end

    it "accepts :mode" do
      magick = pipeline.composite(landscape, mode: "Over").call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-compose", "Over", "-composite"])
    end

    it "accepts deprecated :compose" do
      magick = pipeline.composite(landscape, compose: "Over").call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-compose", "Over", "-composite"])
    end

    it "accepts :gravity" do
      magick = pipeline.composite(landscape, gravity: "Center").call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-gravity", "Center", "-composite"])
    end

    it "accepts :offset" do
      magick = pipeline.composite(landscape, offset: [5, -15]).call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-geometry", "+5-15", "-composite"])
    end

    it "accepts deprecated :geometry" do
      magick = pipeline.composite(landscape, geometry: "+0+0").call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-geometry", "+0+0", "-composite"])
    end

    it "accepts :args" do
      magick = pipeline.composite(landscape, mode: "blend", args: "50,50").call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-compose", "blend", "-define", "compose:args=50,50", "-composite"])
    end

    it "accepts a block" do
      magick = pipeline.composite(landscape) { |m| m.as(MiniMagick::Tool).negate }.call(save: false).as(MiniMagick::Tool)
      magick.args[3..].should eq(["-negate", "-composite"])
    end

    it "has default behaviour without arguments" do
      result1 = pipeline.append(landscape.path).composite!.as(ImageProcessing::Tempfile)
      result2 = pipeline.composite!(landscape.path).as(ImageProcessing::Tempfile)

      assert_similar result1.path, result2.path
    end
  end

  describe "#define" do
    it "adds -define options from a Hash" do
      magick = ImageProcessing::MiniMagick
        .source(portrait)
        .define({"png" => {"compression_level" => 8, "format" => "png8"}})
        .call(save: false)
        .as(MiniMagick::Tool)

      magick.args[2..].should eq(["-define", "png:compression-level=8", "-define", "png:format=png8"])
    end

    it "adds -define options from a String" do
      magick = ImageProcessing::MiniMagick
        .source(portrait)
        .define("png:compression-level=8")
        .call(save: false)
        .as(MiniMagick::Tool)

      magick.args[2..].should eq(["-define", "png:compression-level=8"])
    end
  end

  describe "#limits" do
    it "adds resource limits" do
      pipeline = ImageProcessing::MiniMagick.limits({"width" => 1}).source(portrait)
      exception = expect_raises(MiniMagick::Error) { pipeline.call }
      exception.message.to_s.should contain("limit")
    end
  end

  describe "#append" do
    it "appends CLI arguments" do
      actual = ImageProcessing::MiniMagick.append("-resize", "400x400").call(portrait).as(ImageProcessing::Tempfile)
      expected = ImageProcessing::Tempfile.new("result", ".jpg")
      MiniMagick.convert do |cmd|
        cmd << portrait.path
        cmd.resize("400x400")
        cmd << expected.path
      end

      assert_similar expected.path, actual.path
    end

    it "still supports -append" do
      result = ImageProcessing::MiniMagick.append("wizard:").append.call(portrait).as(ImageProcessing::Tempfile)
      assert_dimensions [600, 1440], result
    end
  end
end
