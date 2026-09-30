# frozen_string_literal: true

require 'open3'

module Shaka
  # Captures a reviewer process with a deadline and terminates its process group on timeout.
  module LocalReviewProcess
    DrainTimeout = Struct.new(:process_status) do
      def success? = false
    end

    def self.capture(arguments, stdin_data:, chdir:, timeout:, env: {})
      Open3.popen3(env, *arguments, chdir: chdir, pgroup: true) do |stdin, stdout, stderr, waiter|
        capture_streams([stdin, stdout, stderr], waiter, stdin_data, timeout)
      end
    end

    def self.capture_streams(streams, waiter, input, timeout)
      stdin, stdout, stderr = streams
      # Reviewer CLIs emit UTF-8 whatever the host locale; a US-ASCII default breaks parsing.
      [stdout, stderr].each { |stream| stream.set_encoding(Encoding::UTF_8) }
      writer = Thread.new { write_input(stdin, input) }
      out_reader = Thread.new { stdout.read }
      err_reader = Thread.new { stderr.read }
      status = wait_or_terminate(waiter, [writer, out_reader, err_reader], timeout)
      [thread_output(out_reader), thread_output(err_reader), status]
    end

    def self.wait_or_terminate(waiter, threads, timeout)
      # Give pipes a separate bounded drain period after the process exits.
      # Reusing the process deadline would reject already-finished readers at its edge.
      exited = waiter.join(timeout)
      unless exited
        terminate(waiter)
        return nil
      end

      drained = join_before_deadline(threads, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2)
      return waiter.value if drained

      terminate(waiter)
      DrainTimeout.new(waiter.value)
    end

    def self.write_input(stdin, data)
      stdin.write(data) if data
    rescue Errno::EPIPE, IOError
      nil
    ensure
      stdin.close unless stdin.closed?
    end

    def self.join_before_deadline(threads, deadline)
      threads.all? do |thread|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        !thread.alive? || (remaining.positive? && thread.join(remaining))
      end
    end

    def self.terminate(waiter)
      Process.kill('TERM', -waiter.pid)
      waiter.join(2)
      Process.kill('KILL', -waiter.pid)
      waiter.join
    rescue Errno::ESRCH
      waiter.join
    end

    def self.thread_output(thread)
      thread.join(2)
      thread.alive? ? '' : thread.value
    rescue IOError
      ''
    end
  end
end
