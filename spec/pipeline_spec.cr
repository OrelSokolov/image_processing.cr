require "./spec_helper"

def pipeline_result(callable) : ImageProcessing::Tempfile
  result = callable.call
  fail("expected Tempfile") unless result.is_a?(ImageProcessing::Tempfile)
  result
end

describe ImageProcessing::Pipeline do
  portrait = fixture_image("portrait.jpg")

  it "accepts source" do
    pipeline = ImageProcessing::Vips.source(portrait)
    pipeline.options.source.as(File).path.should eq(portrait.path)
  end

  it "accepts File, Tempfile, String, and Path objects as source" do
    ImageProcessing::Vips.source(portrait).call
    ImageProcessing::Vips.source(copy_to_tempfile(portrait, "jpg")).call
    ImageProcessing::Vips.source(portrait.path).call
    ImageProcessing::Vips.source(Path.new(portrait.path)).call
  end

  it "accepts format" do
    pipeline = ImageProcessing::Vips.source(portrait)

    result = pipeline_result(-> { pipeline.convert!("png").as(ImageProcessing::Tempfile) })
    File.extname(result.path).should eq(".png")

    result = pipeline_result(-> { pipeline.convert!(nil).as(ImageProcessing::Tempfile) })
    File.extname(result.path).should eq(".jpg")
    assert_similar portrait.path, result.path
  end

  it "retains original format if format was not specified" do
    jpg = ImageProcessing::Vips.convert("jpg").call(portrait).as(ImageProcessing::Tempfile)
    png = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    result_jpg = ImageProcessing::Vips.invert.call(jpg).as(ImageProcessing::Tempfile)
    result_png = ImageProcessing::Vips.invert.call(png).as(ImageProcessing::Tempfile)
    File.extname(result_jpg.path).should eq(".jpg")
    File.extname(result_png.path).should eq(".png")
  end

  it "saves as JPEG when format is unknown" do
    png = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    result = ImageProcessing::Vips.invert.call(copy_to_tempfile(png)).as(ImageProcessing::Tempfile)
    File.extname(result.path).should eq(".jpg")
    assert_type "JPEG", result
  end

  it "saves as JPEG when format is unknown and the path ends with a '.'" do
    png = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    result = ImageProcessing::Vips.invert.call(copy_to_tempfile(png, ".")).as(ImageProcessing::Tempfile)
    File.extname(result.path).should eq(".jpg")
    assert_type "JPEG", result
  end

  it "accepts destination path" do
    destination = ImageProcessing::Tempfile.new("destination", ".jpg")
    ImageProcessing::Vips.source(portrait).call(destination: destination.path)
    File.size(destination.path).should_not eq(0)
  end

  it "makes sure the destination file is deleted on processing errors" do
    destination_path = tempname("destination", ".jpg")
    pipeline = ImageProcessing::MiniMagick.source(fixture_image("invalid.jpg"))
    expect_raises(MiniMagick::Error) { pipeline.call(destination: destination_path) }
    File.exists?(destination_path).should be_false
  end

  it "doesn't delete the destination file if it has already existed" do
    destination = ImageProcessing::Tempfile.new("destination", ".jpg")
    pipeline = ImageProcessing::MiniMagick.source(fixture_image("invalid.jpg"))
    expect_raises(MiniMagick::Error) { pipeline.call(destination: destination.path) }
    File.exists?(destination.path).should be_true
  end

  it "doesn't fail when destination file hasn't been created" do
    destination_path = tempname("destination")
    pipeline = ImageProcessing::Vips.source(portrait)
    expect_raises(Vips::Error) { pipeline.call(destination: destination_path) }
  end

  it "accepts loader options" do
    pipeline = ImageProcessing::Vips.loader(shrink: 2)
    pipeline.options.loader.should eq({"shrink" => 2})

    pipeline = pipeline.loader(autorotate: true)
    pipeline.options.loader.should eq({"shrink" => 2, "autorotate" => true})
  end

  it "accepts saver options" do
    pipeline = ImageProcessing::Vips.saver(strip: true)
    pipeline.options.saver.should eq({"strip" => true})

    pipeline = pipeline.saver(Q: 100)
    pipeline.options.saver.should eq({"strip" => true, "Q" => 100})
  end

  it "accepts operations" do
    pipeline = ImageProcessing::Vips.shrink(2, 2)
    pipeline.options.operations.map { |op| {op.name, op.args} }.should eq([{"shrink", [2, 2]}])

    pipeline = pipeline.invert
    pipeline.options.operations.map { |op| {op.name, op.args} }.should eq(
      [{"shrink", [2, 2]}, {"invert", [] of ImageProcessing::OptValue}])
  end

  it "saves blocks passed to operations" do
    pipeline = ImageProcessing::MiniMagick.stack { |stack| stack.as(MiniMagick::Tool).foo("bar") }
    first = pipeline.options.operations.first
    first.name.should eq("stack")
    first.args.empty?.should be_true
    first.block.should_not be_nil
  end

  it "accepts a list of commands" do
    pipeline = ImageProcessing::Vips.source(fixture_image("rotated.jpg"))

    # hash
    actual1 = pipeline
      .apply({
        loader:        {"autorotate" => true},
        resize_to_fit: [400, 400, {"sharpen" => false}],
        invert:        true,
        rot90:         nil,
        rot:           "d90",
        convert:       "png",
      })
      .call.as(ImageProcessing::Tempfile)

    # array
    actual2 = pipeline
      .apply([
        {"loader", {"autorotate" => true}},
        {"resize_to_fit", [400, 400, {"sharpen" => false}]},
        {"invert", true},
        {"rot90", nil},
        {"rot", "d90"},
        {"convert", "png"},
      ])
      .call.as(ImageProcessing::Tempfile)

    expected = pipeline
      .loader(autorotate: true)
      .resize_to_fit(400, 400, sharpen: false)
      .invert
      .rot90
      .rot("d90")
      .convert("png")
      .call.as(ImageProcessing::Tempfile)

    assert_similar expected.path, actual1.path
    assert_similar expected.path, actual2.path
  end

  it "applies a custom block" do
    actual = ImageProcessing::Vips.custom { |image| image.as(Vips::Image).invert.as(Vips::Image) }
      .call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Vips.invert.call(portrait).as(ImageProcessing::Tempfile)
    assert_similar expected.path, actual.path

    actual = ImageProcessing::Vips.custom { |image| nil }.call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Vips.call(portrait).as(ImageProcessing::Tempfile)
    assert_similar expected.path, actual.path

    identity = ImageProcessing::Vips.custom.call(portrait).as(ImageProcessing::Tempfile)
    assert_similar portrait.path, identity.path
  end

  it "merges different options" do
    pipeline = ImageProcessing::Vips
      .resize_to_fill(400, 400)
      .convert("png")

    pipeline.options.operations.map { |op| {op.name, op.args} }.should eq([{"resize_to_fill", [400, 400]}])
    pipeline.options.format.should eq("png")
  end

  it "doesn't mutate the receiver when branching" do
    pipeline_jpg = ImageProcessing::Vips.convert("jpg")
    pipeline_png = pipeline_jpg.convert("png")

    pipeline_jpg.options.format.should eq("jpg")
    pipeline_png.options.format.should eq("png")
  end

  it "executes processing on #call with source" do
    result = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    result.should be_a(ImageProcessing::Tempfile)
    assert_type "PNG", result
  end

  it "executes processing on #call without source" do
    result = ImageProcessing::Vips.source(portrait).convert("png").call.as(ImageProcessing::Tempfile)
    result.should be_a(ImageProcessing::Tempfile)
    assert_type "PNG", result
  end

  it "executes processing on bang operation method" do
    result = ImageProcessing::Vips.source(portrait).convert!("png").as(ImageProcessing::Tempfile)
    result.should be_a(ImageProcessing::Tempfile)
    assert_type "PNG", result

    result = ImageProcessing::Vips.source(portrait).shrink!(2, 2).as(ImageProcessing::Tempfile)
    result.should be_a(ImageProcessing::Tempfile)
    assert_dimensions [300, 400], result

    result = ImageProcessing::Vips.source(portrait).resize_to_fill!(400, 400).as(ImageProcessing::Tempfile)
    result.should be_a(ImageProcessing::Tempfile)
    assert_dimensions [400, 400], result
  end

  it "can be called directly" do
    result = ImageProcessing::Vips.call(portrait).as(ImageProcessing::Tempfile)
    assert_similar result.path, portrait.path
  end

  it "applies a sequence of operations" do
    actual = ImageProcessing::Vips
      .invert
      .shrink(2, 2)
      .call(portrait).as(ImageProcessing::Tempfile)

    expected = ImageProcessing::Vips.invert.call(portrait).as(ImageProcessing::Tempfile)
    expected = ImageProcessing::Vips.shrink(2, 2).call(expected).as(ImageProcessing::Tempfile)

    assert_similar expected.path, actual.path
  end

  it "returns a rewinded and refreshed tempfile in binary mode" do
    tempfile = ImageProcessing::Vips.convert("png").call(portrait).as(ImageProcessing::Tempfile)
    tempfile.should be_a(ImageProcessing::Tempfile)
    tempfile.binmode?.should be_true
    tempfile.pos.should eq(0)
    tempfile.read.should eq(File.read(tempfile.path))
  end

  it "returns an intermediary object on #call(save: false)" do
    vips_image = ImageProcessing::Vips.resize_to_limit(400, 400).call(portrait, save: false).as(Vips::Image)
    vips_image.should be_a(Vips::Image)
    vips_image.size.should eq([300, 400])

    magick = ImageProcessing::MiniMagick.source(portrait).resize_to_limit(400, 400).call(save: false).as(MiniMagick::Tool)
    magick.should be_a(MiniMagick::Tool)
    magick.args.should contain("400x400>")
  end

  it "raises exception when source was not provided" do
    expect_raises(ImageProcessing::Error) do
      ImageProcessing::Vips.call
    end
  end

  it "raises exception when invalid source was provided" do
    expect_raises(ImageProcessing::Error) do
      ImageProcessing::Vips.source(true).call
    end
  end

  it "raises a NoMethodError when predicate method is not defined" do
    expect_raises(ImageProcessing::NoMethodError) do
      ImageProcessing::Vips.valid?(portrait)
    end
  end

  it "doesn't allow making system calls" do
    ImageProcessing::Vips.source(portrait).apply({system: "touch foo.txt"})
    File.exists?("foo.txt").should be_false

    expect_raises(Vips::Error) do
      ImageProcessing::Vips.source(portrait).spawn("touch foo.txt").call
    end
    File.exists?("foo.txt").should be_false

    expect_raises(MiniMagick::Error) do
      ImageProcessing::MiniMagick.source(portrait).spawn("touch foo.txt").call
    end
    File.exists?("foo.txt").should be_false
  end
end
