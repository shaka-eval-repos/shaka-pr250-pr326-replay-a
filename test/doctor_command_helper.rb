# frozen_string_literal: true

require 'shaka/doctor'

# Support for the bounded-command tests: each one states the child it describes and measures
# how long the command took to answer, because a deadline that silently waits is the exact
# failure these tests exist to catch.
module DoctorCommandHelper
  # SIGKILL is uncatchable, so an undeliverable signal is simulated by not sending one.
  class UnkillableCommand < Shaka::Doctor::BoundedCommand
    private

    def terminate(_pid) = nil
  end

  # Stands in for an interrupt arriving while the command waits on its child. It records the
  # pid it spawned, so the check does not race the child writing one down.
  class InterruptedCommand < Shaka::Doctor::BoundedCommand
    attr_reader :spawned

    def initialize(timeout:, after: 0)
      super(timeout: timeout)
      @after = after
    end

    private

    def start(child, argv, options)
      super
      @spawned = child.process.pid
    end

    # `after` lets the leader exit first, so the interrupt can arrive while only a descendant
    # is still holding the pipes.
    def drained?(*)
      sleep @after
      raise Interrupt
    end
  end

  # Delivers a real asynchronous interrupt in the one interval that matters: after the child
  # exists and before the call has recorded it. Raising after `start` returns would prove
  # nothing, because by then every handle is published.
  class InterruptedInsideSpawnCommand < Shaka::Doctor::BoundedCommand
    attr_reader :spawned

    private

    def spawn(argv, options)
      result = super
      @spawned = result.last.pid
      target = Thread.current
      Thread.new { target.raise(Interrupt) }.join
      sleep 0.05 # a safe point, so an undeferred interrupt lands here rather than later
      result
    end
  end

  def run_bounded(timeout, argv, chdir = nil)
    Shaka::Doctor::BoundedCommand.new(timeout: timeout).call(argv, chdir)
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, result]
  end

  def pid_in(path) = Integer(File.read(path).strip)

  # Signalling the leader alone orphans whatever it started, which is the very leak the
  # command under test prevents. Teardown kills the group and waits for it to empty; a group
  # with no members answers ESRCH.
  def kill_group_and_wait(pgid, within: 5)
    kill_quietly(-pgid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return unless alive?(-pgid)

      sleep 0.05
    end
    flunk 'the test left a process group running'
  end

  def kill_quietly(pid)
    Process.kill('KILL', pid)
  rescue Errno::ESRCH, Errno::EPERM, ArgumentError
    nil
  end

  # A killed process lingers until its parent reaps it, and a descendant is reparented before
  # init can, so the check waits for it to disappear instead of racing the teardown. A survivor
  # sleeps for thirty seconds and is still there when the wait runs out.
  def refute_alive(pid, message, within: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return unless alive?(pid)

      sleep 0.05
    end
    flunk message
  end

  # Only ESRCH means nothing is there. EPERM means something is, and cannot be signalled from
  # here — which a group being torn down can answer transiently — so it counts as alive and the
  # caller keeps waiting. A genuine survivor still runs the wait out and fails.
  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end
end
