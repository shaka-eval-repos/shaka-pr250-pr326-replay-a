# frozen_string_literal: true

require 'open3'

module Shaka
  class Doctor
    # Runs one child command under a deadline, so a stalled command becomes a check's answer
    # instead of stopping the whole report.
    #
    # Three details carry the behavior. The child leads its own process group, so expiry can
    # signal the group rather than a shell that has already handed work to a descendant. Both
    # pipes are drained while the child runs, because a child that fills a pipe buffer blocks
    # forever if its output is read only after it exits. And `popen3` is used without a block,
    # because the block form joins the child during cleanup and would wait out the very hang
    # this bounds.
    class BoundedCommand
      READ_SIZE = 4096
      # SIGKILL to the group normally lands at once. This bounds the one case where it cannot —
      # an undeliverable signal — so cleanup can never reintroduce the hang this class removes.
      GRACE = 1

      # One invocation's handles. Built before the spawn, so cleanup never depends on an
      # assignment that may not have happened, and per call, so the shared runner stays stateless.
      Child = Struct.new(:process, :stdout, :stderr, :answered)

      def initialize(timeout:)
        @timeout = timeout
      end

      def call(argv, chdir = nil)
        child = Child.new
        start(child, argv, spawn_options(chdir))
        result = collect(child.stdout, child.stderr, child.process)
        child.answered = true
        result
      ensure
        release(child)
      end

      private

      def spawn_options(chdir)
        chdir ? { pgroup: true, chdir: chdir } : { pgroup: true }
      end

      # Every handle the cleanup needs is recorded before any interrupt can be delivered.
      # A local assigned after the fork is not good enough: an interrupt landing in between
      # leaves a child in its own process group, which the terminal's Ctrl-C never reaches
      # and nothing else knows about.
      def start(child, argv, options)
        Thread.handle_interrupt(Interrupt => :never) do
          stdin, stdout, stderr, process = spawn(argv, options)
          child.stdout = stdout
          child.stderr = stderr
          child.process = process
          stdin.close
        end
      end

      def spawn(argv, options) = Open3.popen3(*argv, **options)

      # `pgroup: true` isolates the child from the terminal, so leaving by exception has to
      # take the group with it or interrupting doctor strands the very process it was
      # bounding. A call that answered has already cleaned up after a timeout and has nothing
      # to clean up after success.
      def release(child)
        cleanup(child.process) if child.process && !child.answered
        [child.stdout, child.stderr].each { |io| io.close unless io.nil? || io.closed? }
      end

      def collect(stdout, stderr, process)
        streams = { stdout => +''.b, stderr => +''.b }
        deadline = now + @timeout
        return expired(process) unless drained?(streams, deadline) && exited?(process, deadline)

        [text(streams.fetch(stdout)), text(streams.fetch(stderr)), process.value.success?]
      end

      # read_nonblock answers binary, unlike the buffered read it replaced. A caller puts this
      # straight into a UTF-8 message, so a localized error from the command would raise an
      # encoding error and take down the report. Scrub makes that impossible.
      def text(buffer) = buffer.force_encoding(Encoding::UTF_8).scrub

      # Returns false once the deadline passes, so a child that never closes its pipes and a
      # child that floods them are both bounded.
      def drained?(streams, deadline)
        open = streams.keys
        until open.empty?
          remaining = deadline - now
          return false unless remaining.positive?

          ready = IO.select(open, nil, nil, remaining)
          return false unless ready

          read(ready.first, streams, open)
        end
        true
      end

      def read(ready, streams, open)
        ready.each do |io|
          streams[io] << io.read_nonblock(READ_SIZE)
        rescue IO::WaitReadable
          next
        rescue EOFError
          open.delete(io)
        end
      end

      # Closed pipes usually mean the child is gone, but a child can close them and keep
      # running, so the wait is bounded too.
      def exited?(process, deadline)
        remaining = deadline - now
        remaining.positive? && !process.join(remaining).nil?
      end

      def expired(process)
        cleanup(process)
        ['', "no answer within #{@timeout}s", false]
      end

      def cleanup(process)
        terminate(process.pid)
        process.join(GRACE)
      end

      # The whole group, addressed by the pid it was created with. `pgroup: true` makes the
      # child its own group leader, so the group id is that pid — and asking the system for it
      # at expiry would fail exactly when it matters, because the leader can exit and be reaped
      # while a descendant holds the pipes open and keeps running.
      def terminate(pid)
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
