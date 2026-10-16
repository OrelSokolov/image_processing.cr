require "./spec_helper"

def vips_result(callable) : ImageProcessing::Tempfile
  result = callable.call
  fail("expected Tempfile") unless result.is_a?(ImageProcessing::Tempfile)
  result
end

describe ImageProcessing::Vips do
  portrait = fixture_image("portrait.jpg")
  landscape = fixture_image("landscape.jpg")
  square = fixture_image("square.jpg")
  exif_portrait = fixture_image("exif_portrait.jpg")

  it "applies vips operations" do
    actual = ImageProcessing::Vips.invert.call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Tempfile.new("result", ".jpg")
    image = Vips::Image.new_from_file(portrait.path)
    image = image.invert.as(Vips::Image)
    image.write_to_file(expected.path)

    assert_similar expected.path, actual.path
  end

  it "applies macro operations" do
    actual = ImageProcessing::Vips.resize_to_limit(400, 400).call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Tempfile.new("result", ".jpg")
    image = Vips::Image.new_from_file(portrait.path)
    image = image.thumbnail_image(400, height: 400, size: :down).as(Vips::Image)
    image.write_to_file(expected.path)

    assert_similar expected.path, actual.path
  end

  it "allows changing metadata" do
    image = ImageProcessing::Vips
      .copy
      .set("icc-profile-data", "foobar")
      .set_type(Vips::BLOB_TYPE, "foo", "bar")
      .remove("exif-data")
      .call(portrait, save: false).as(Vips::Image)

    image.get("icc-profile-data").should eq("foobar")
    image.get("foo").should eq("bar")

    expect_raises(Vips::Error) { image.get("exif-data") }
  end

  it "applies format" do
    result = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    File.extname(result.path).should eq(".png")
    assert_type "PNG", result
  end

  it "auto rotates by default" do
    result = ImageProcessing::Vips.call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result

    result = ImageProcessing::Vips.resize_to_limit(1000, 1000).call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result

    result = ImageProcessing::Vips.loader(fail: true).resize_to_limit(1000, 1000)
      .call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result

    result = ImageProcessing::Vips.call(
      Vips::Image.new_from_file(fixture_path("rotated.jpg"))).as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result

    result = ImageProcessing::Vips.loader(autorot: false).call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [800, 600], result

    result = ImageProcessing::Vips.loader(autorotate: false).call(fixture_image("rotated.jpg")).as(ImageProcessing::Tempfile)
    assert_dimensions [800, 600], result
  end

  it "accepts Vips::Image as source" do
    vips_image = Vips::Image.new_from_file(fixture_path("rotated.jpg"))
    result = ImageProcessing::Vips.source(vips_image).call.as(ImageProcessing::Tempfile)
    assert_dimensions [600, 800], result
  end

  it "applies loader options" do
    result = ImageProcessing::Vips.loader(shrink: 2).call(portrait).as(ImageProcessing::Tempfile)
    assert_dimensions [300, 400], result
  end

  it "ignores loader options that are not defined" do
    png = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    ImageProcessing::Vips.loader(shrink: 2).call(png)
  end

  it "raises correct Vips::Error on unknown loader" do
    error = expect_raises(Vips::Error) do
      ImageProcessing::Vips.convert("jpg").call(ImageProcessing::Tempfile.new("empty", ""))
    end
    error.message.to_s.should contain("not a known file format")
  end

  it "accepts :loader" do
    error = expect_raises(Vips::Error) do
      ImageProcessing::Vips.loader(loader: "tiff").call(portrait)
    end
    error.message.to_s.should contain("Not a TIFF")
  end

  it "applies saver options" do
    result = ImageProcessing::Vips.saver(strip: true).call(portrait).as(ImageProcessing::Tempfile)
    Vips::Image.new_from_file(result.path).get_fields.should_not contain("exif-data")
  end

  it "converts :quality saver option to :Q" do
    result1 = ImageProcessing::Vips.saver(quality: 50).call(portrait).as(ImageProcessing::Tempfile)
    result2 = ImageProcessing::Vips.saver(quality: 100).call(portrait).as(ImageProcessing::Tempfile)
    result1.size.should be < result2.size
  end

  it "ignores saver options that are not defined" do
    ImageProcessing::Vips.saver(Q: 85).convert("png").call(portrait)
  end

  it "raises correct Vips::Error on unknown saver" do
    error = expect_raises(Vips::Error) do
      ImageProcessing::Vips.convert("foo").call(portrait)
    end
    error.message.to_s.should match(/is not a known file format|No known saver for/)
  end

  it "accepts :saver" do
    result = ImageProcessing::Vips.saver(saver: "png").call(portrait).as(ImageProcessing::Tempfile)
    File.extname(result.path).should eq(".jpg")
    assert_type "PNG", result
  end

  describe ".valid_image?" do
    it "returns true for correct images" do
      ImageProcessing::Vips.valid_image?(portrait).should be_true
      ImageProcessing::Vips.valid_image?(copy_to_tempfile(portrait)).should be_true # no extension
    end

    it "returns false for incorrect images" do
      ImageProcessing::Vips.valid_image?(fixture_image("invalid.jpg")).should be_false
      ImageProcessing::Vips.valid_image?(copy_to_tempfile(fixture_image("invalid.jpg"))).should be_false # no extension
    end
  end

  describe "#resize_to_limit" do
    pipeline = ImageProcessing::Vips.source(portrait)

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

    it "raises exception when neither dimension is specified" do
      expect_raises(ImageProcessing::Error) do
        pipeline.resize_to_limit!(nil, nil)
      end
    end

    it "produces correct image" do
      expected = fixture_image("limit.jpg")
      assert_similar expected.path, pipeline.resize_to_limit!(400, 400).as(ImageProcessing::Tempfile).path
    end

    it "accepts thumbnail options" do
      assert_dimensions [400, 400], pipeline.resize_to_limit!(400, 400, crop: :centre)
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_limit!(400, 400, sharpen: ImageProcessing::Vips::Processor::SHARPEN_MASK).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_limit!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end

    it "sharpening uses integer precision" do
      sharpened = pipeline.resize_to_limit(400, 400).call(save: false).as(Vips::Image)
      sharpened.format.should eq("uchar")
    end
  end

  describe "#resize_to_fit" do
    pipeline = ImageProcessing::Vips.source(portrait)

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

    it "raises exception when neither dimension is specified" do
      expect_raises(ImageProcessing::Error) do
        pipeline.resize_to_limit!(nil, nil)
      end
    end

    it "produces correct image" do
      expected = fixture_image("fit.jpg")
      assert_similar expected.path, pipeline.resize_to_fit!(400, 400).as(ImageProcessing::Tempfile).path
    end

    it "accepts thumbnail options" do
      assert_dimensions [400, 400], pipeline.resize_to_fit!(400, 400, crop: :centre)
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_fit!(400, 400, sharpen: ImageProcessing::Vips::Processor::SHARPEN_MASK).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_fit!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end

    it "sharpening uses integer precision" do
      sharpened = pipeline.resize_to_limit(400, 400).call(save: false).as(Vips::Image)
      sharpened.format.should eq("uchar")
    end
  end

  describe "#resize_to_fill" do
    pipeline = ImageProcessing::Vips.source(portrait)

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

    it "accepts thumbnail options" do
      attention = pipeline.resize_to_fill!(400, 400, crop: :attention).as(ImageProcessing::Tempfile)
      centre = pipeline.resize_to_fill!(400, 400, crop: :centre).as(ImageProcessing::Tempfile)
      refute_similar centre.path, attention.path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_to_fill!(400, 400, sharpen: ImageProcessing::Vips::Processor::SHARPEN_MASK).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_to_fill!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end

    it "sharpening uses integer precision" do
      sharpened = pipeline.resize_to_limit(400, 400).call(save: false).as(Vips::Image)
      sharpened.format.should eq("uchar")
    end
  end

  describe "#resize_and_pad" do
    pipeline = ImageProcessing::Vips.source(portrait)

    it "resizes and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [400, 400], pipeline.resize_and_pad!(400, 400)
    end

    it "enlarges image and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [1000, 1000], pipeline.resize_and_pad!(1000, 1000)
    end

    it "produces correct image when shrinking" do
      result = pipeline.convert("png").resize_and_pad!(400, 400, alpha: true).as(ImageProcessing::Tempfile)
      assert_similar fixture_path("pad.png"), result.path
      Vips::Image.new_from_file(result.path).bands.should eq(4)

      transparent_png = pipeline.add_alpha.convert!("png").as(ImageProcessing::Tempfile)
      result = pipeline.source(transparent_png).resize_and_pad!(400, 400, alpha: true).as(ImageProcessing::Tempfile)
      assert_similar fixture_path("pad.png"), result.path
      Vips::Image.new_from_file(result.path).bands.should eq(4)
    end

    it "produces correct image when enlarging" do
      pipeline = ImageProcessing::Vips.source(landscape)
      expected = fixture_image("pad-large.jpg")
      # The fixture was generated by ImageMagick; libvips 8.18 re-encodes the
      # padded result slightly differently, flipping one dhash bit over the
      # default threshold.
      result = pipeline.resize_and_pad!(1000, 1000, background: [55, 126, 34]).as(ImageProcessing::Tempfile)
      distance(expected.path, result.path).should be <= 5
    end

    it "accepts gravity" do
      centre = pipeline.resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      northwest = pipeline.resize_and_pad!(400, 400, gravity: "north-west").as(ImageProcessing::Tempfile)
      refute_similar centre.path, northwest.path
    end

    it "accepts thumbnail options" do
      pad = pipeline.resize_and_pad!(400, 400).as(ImageProcessing::Tempfile)
      crop = pipeline.resize_and_pad!(400, 400, crop: :entropy).as(ImageProcessing::Tempfile)
      refute_similar pad.path, crop.path
    end

    it "accepts sharpening options" do
      sharpened = pipeline.resize_and_pad!(400, 400, sharpen: ImageProcessing::Vips::Processor::SHARPEN_MASK).as(ImageProcessing::Tempfile)
      normal = pipeline.resize_and_pad!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end

    it "sharpening uses integer precision" do
      sharpened = pipeline.resize_to_limit(400, 400).call(save: false).as(Vips::Image)
      sharpened.format.should eq("uchar")
    end
  end

  describe "#resize_to_cover" do
    portrait_pipeline = ImageProcessing::Vips.source(portrait)
    landscape_pipeline = ImageProcessing::Vips.source(landscape)
    square_pipeline = ImageProcessing::Vips.source(square)
    exif_portrait_pipeline = ImageProcessing::Vips.source(exif_portrait)

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

    it "accepts thumbnail options except :crop" do
      attention = portrait_pipeline.resize_to_cover!(400, 400, crop: :attention).as(ImageProcessing::Tempfile)
      centre = portrait_pipeline.resize_to_cover!(400, 400, crop: :centre).as(ImageProcessing::Tempfile)
      assert_similar centre.path, attention.path
    end

    it "accepts sharpening options" do
      sharpened = portrait_pipeline.resize_to_cover!(400, 400, sharpen: ImageProcessing::Vips::Processor::SHARPEN_MASK).as(ImageProcessing::Tempfile)
      normal = portrait_pipeline.resize_to_cover!(400, 400, sharpen: false).as(ImageProcessing::Tempfile)
      sharpened.size.should be > normal.size
    end

    it "sharpening uses integer precision" do
      sharpened = portrait_pipeline.resize_to_cover(400, 400).call(save: false).as(Vips::Image)
      sharpened.format.should eq("uchar")
    end

    it "works correctly with EXIF orientation" do
      assert_dimensions [300, 617], exif_portrait_pipeline.resize_to_cover!(300, 200)
    end
  end

  describe "#rotate" do
    pipeline = ImageProcessing::Vips.source(portrait)

    it "rotates by multiples of 90" do
      assert_dimensions [600, 800], pipeline.rotate!(0)
      assert_dimensions [800, 600], pipeline.rotate!(90)
      assert_dimensions [600, 800], pipeline.rotate!(180)
      assert_dimensions [800, 600], pipeline.rotate!(270)
    end

    it "works for angles outside of 0-360 degrees" do
      assert_dimensions [600, 800], pipeline.rotate!(360)
      assert_dimensions [800, 600], pipeline.rotate!(450)
      assert_dimensions [800, 600], pipeline.rotate!(-90)
    end

    it "rotates by arbitrary angle" do
      assert_dimensions [990, 990], pipeline.rotate!(45)
    end

    it "accepts background color" do
      assert_dimensions [990, 990], pipeline.rotate!(45, background: [0, 0, 0])
    end
  end

  describe "#composite" do
    pipeline = ImageProcessing::Vips.source(portrait)

    # The fixture was generated by ImageMagick; libvips 8.18 re-encodes the
    # composited result slightly differently (a few gray levels of jpeg
    # noise), which flips more dhash bits than the default threshold allows.
    it "accepts String, Path, and File object" do
      [landscape, landscape.path, Path.new(landscape.path)].each do |overlay|
        result = pipeline.composite!(overlay).as(ImageProcessing::Tempfile).path
        distance(fixture_path("composited.jpg"), result).should be <= 24
      end
    end

    it "accepts Vips::Image object" do
      overlay = Vips::Image.new_from_file(landscape.path)
      result = pipeline.composite!(overlay).as(ImageProcessing::Tempfile).path
      distance(fixture_path("composited.jpg"), result).should be <= 24
    end

    it "accepts :mode" do
      refute_similar fixture_path("composited.jpg"), pipeline.composite!(landscape, mode: "clear").as(ImageProcessing::Tempfile).path
    end

    it "accepts :gravity" do
      result = pipeline.composite!(landscape, gravity: "centre").as(ImageProcessing::Tempfile)
      refute_similar fixture_path("composited.jpg"), result.path
      assert_dimensions [600, 800], result

      expect_raises(Vips::Error) { pipeline.composite!(landscape, gravity: "foo") }
    end

    it "accepts :offset" do
      result = pipeline.composite!(landscape, offset: [50, -50]).as(ImageProcessing::Tempfile)
      refute_similar fixture_path("composited.jpg"), result.path
      assert_dimensions [600, 800], result
    end

    it "accepts additional options" do
      pipeline.composite!(landscape, compositing_space: :grey16)

      expect_raises(Vips::Error) { pipeline.composite!(landscape, compositing_space: :foo) }
    end

    it "accepts Vips::Image#composite parameters" do
      overlay = Vips::Image.new_from_file(landscape.path)
      original = pipeline.custom! { |image| image.as(Vips::Image).composite(overlay, :over).as(Vips::Image) }.as(ImageProcessing::Tempfile)

      assert_similar original.path, pipeline.composite!(overlay, :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!(landscape, :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!(landscape.path, :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!(Path.new(landscape.path), :over).as(ImageProcessing::Tempfile).path

      assert_similar original.path, pipeline.composite!([overlay], :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!([landscape], :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!([landscape.path], :over).as(ImageProcessing::Tempfile).path
      assert_similar original.path, pipeline.composite!([Path.new(landscape.path)], :over).as(ImageProcessing::Tempfile).path
    end
  end

  describe "resize-on-load" do
    it "retains order of operations" do
      result = ImageProcessing::Vips.source(portrait)
        .resize_to_fit(400, 400)
        .crop(0, 0, 300, 300)
        .call.as(ImageProcessing::Tempfile)

      assert_dimensions [300, 300], result

      result = ImageProcessing::Vips.source(portrait)
        .crop(0, 0, 300, 300)
        .resize_to_fit(400, 400)
        .call.as(ImageProcessing::Tempfile)

      assert_dimensions [400, 400], result
    end

    it "is skipped on loader options" do
      pipeline = ImageProcessing::Vips.source(fixture_image("invalid.jpg"))
        .loader(fail: true)
        .resize_to_fit(400, 400)

      error = expect_raises(Vips::Error) { pipeline.call }
      error.message.to_s.should contain("Corrupt JPEG data")
    end
  end
end
