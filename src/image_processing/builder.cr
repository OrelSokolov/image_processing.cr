module ImageProcessing
  class Builder(P, Acc)
    include Chainable(P, Acc)

    getter options : Options

    def initialize(@options : Options)
    end

    # Calls the pipeline to perform the processing from built options.
    def call!(**call_options) : Tempfile | Acc | Nil
      instrumenter = @options.instrumenter
      return Pipeline(P, Acc).new(pipeline_options).call(**call_options) unless instrumenter

      result = nil.as(Tempfile | Acc | Nil)
      instrumenter.call(pipeline_options, -> {
        result = Pipeline(P, Acc).new(pipeline_options).call(**call_options)
      })
      result
    end

    private def pipeline_options : Options
      options = @options.dup
      options.instrumenter = nil
      options
    end
  end
end
