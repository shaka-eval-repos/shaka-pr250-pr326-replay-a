# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/links'
require 'io/wait'
require 'English'

class InstallLinkLockTest < Minitest::Test
  include InstallTestSupport

  def test_link_switch_waits_for_skills_directory_lock
    skip 'fork unavailable' unless Process.respond_to?(:fork)

    FileUtils.mkdir_p(@skills_dir)
    target = File.join(@directory, 'managed', 'package')
    FileUtils.mkdir_p(File.join(target, 'skills', 'shaka'))
    path = File.join(@skills_dir, '.shaka-install.lock')
    File.open(path, File::RDWR | File::CREAT, 0o600) { |lock| assert_lock_serializes(lock, target) }
  end

  private

  def assert_lock_serializes(lock, target)
    lock.flock(File::LOCK_EX)
    ready, finished, child = start_waiting_child(target)
    assert_waiting(ready, finished)
    lock.flock(File::LOCK_UN)
    assert_done(finished, child, target)
  ensure
    lock.flock(File::LOCK_UN)
    ready&.close
    finished&.close
    reap(child)
  end

  def assert_waiting(ready, finished)
    assert_equal 'ready', ready.read(5)
    assert_nil finished.wait_readable(0.1)
  end

  def assert_done(finished, child, target)
    assert_equal 'done', finished.read(4)
    Process.wait(child)
    assert_predicate $CHILD_STATUS, :success?
    assert_equal File.join(target, 'skills', 'shaka'), File.readlink(File.join(@skills_dir, 'shaka'))
  end

  def reap(child)
    Process.wait(child) if child
  rescue Errno::ECHILD
    nil
  end

  def start_waiting_child(target)
    ready_read, ready_write = IO.pipe
    done_read, done_write = IO.pipe
    child = fork { child_work(ready_read, ready_write, done_read, done_write, target) }
    ready_write.close
    done_write.close
    [ready_read, done_read, child]
  end

  def child_work(ready_read, ready_write, done_read, done_write, target)
    ready_read.close
    done_read.close
    ready_write.write('ready')
    ready_write.close
    Shaka::Install::Links.new(@skills_dir, File.dirname(target), File.join(@directory, 'source'), ['shaka'])
                         .switch_all(target)
    done_write.write('done')
    done_write.close
    exit! 0
  end
end
