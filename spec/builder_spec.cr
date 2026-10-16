require "./spec_helper"

describe ImageProcessing::Builder do
  portrait = fixture_image("portrait.jpg")

  it "instruments pipeline execution" do
    pipeline = ImageProcessing::Vips
      .source(portrait)
      .loader(shrink: 2)
      .resize_to_limit(500, 500)
      .saver(strip: true)
      .convert("png")

    instrumenter_called = false

    pipeline = pipeline.instrumenter do |options, call|
      instrumenter_called = true

      options.source.as(File).path.should eq(portrait.path)
      options.loader.should eq({"shrink" => 2})
      options.operations.map { |op| {op.name, op.args} }.should eq([{"resize_to_limit", [500, 500]}])
      options.saver.should eq({"strip" => true})
      options.format.should eq("png")

      call.call
      nil
    end

    pipeline.call

    instrumenter_called.should be_true
  end

  it "handles instrumenter not returning pipeline result" do
    pipeline = ImageProcessing::Vips
      .source(portrait)
      .instrumenter do |options, call|
        call.call
        nil
      end

    result = pipeline.call
    result.should be_a(ImageProcessing::Tempfile)
  end
end
