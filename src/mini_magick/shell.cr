module MiniMagick
  # Executes ImageMagick commands, capturing stdout/stderr, mirroring the
  # behavior of mini_magick's MiniMagick::Shell.
  module Shell
    def self.run(cmd : Array(String), errors = true, warnings = true, stdin = nil) : {String, String, Process::Status}
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      input = stdin ? IO::Memory.new(stdin.not_nil!) : Process::Redirect::Close

      status = Process.run(
        cmd[0],
        cmd[1..],
        input: input,
        output: stdout,
        error: stderr
      )

      stdout_s = stdout.to_s
      stderr_s = stderr.to_s

      STDERR.print stderr_s if warnings && !stderr_s.empty?

      if errors && !status.success?
        raise Error.new("`#{cmd.join(" ")}` failed: #{status} #{stderr_s}")
      end

      {stdout_s, stderr_s, status}
    end
  end
end
