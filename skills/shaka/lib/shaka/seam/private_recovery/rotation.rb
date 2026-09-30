# frozen_string_literal: true

module Shaka
  class Seam
    # Preserves both snapshots if installing a new recovery copy fails.
    class PrivateRecovery
      def recovery_copy?
        %w[current previous].any? do |name|
          path = File.join(@storage, name)
          File.exist?(path) || File.symlink?(path)
        end
      end

      def mark_activated!
        File.write(File.join(@storage, 'activated'), "complete\n")
      end

      def mark_incomplete!
        File.unlink(File.join(@storage, 'activated'))
      rescue Errno::ENOENT
        nil
      end

      private

      def with_storage_lock(storage: @storage, create: true)
        FileUtils.mkdir_p(storage, mode: 0o700) if create
        raise Error, "No recovery copy at #{storage}" unless File.directory?(storage)

        File.open(File.join(storage, 'rotation.lock'), File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          yield
        end
      end

      def install_copy(copy, inventory)
        current, previous, aside = rotation_paths
        moves = []
        rotate_existing(current, previous, aside, moves) if File.exist?(current)
        move_for_rotation(copy, current, moves)
        write_manifest(inventory)
        FileUtils.rm_rf(aside)
      rescue StandardError
        rollback_moves(moves)
        raise
      end

      def rollback_moves(moves)
        moves&.reverse_each do |from, to|
          File.rename(to, from)
        rescue SystemCallError
          nil # Continue restoring other copies; the original failure is still reported.
        end
      end

      def rotation_paths
        [File.join(@storage, 'current'), File.join(@storage, 'previous'),
         File.join(@storage, "previous-#{SecureRandom.hex(8)}")]
      end

      def rotate_existing(current, previous, aside, moves)
        move_for_rotation(previous, aside, moves) if File.exist?(previous)
        move_for_rotation(current, previous, moves)
      end

      def move_for_rotation(from, to, moves)
        File.rename(from, to)
        moves << [from, to]
      end
    end
  end
end
