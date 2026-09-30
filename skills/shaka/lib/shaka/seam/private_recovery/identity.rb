# frozen_string_literal: true

module Shaka
  class Seam
    # Assigns a complete identity atomically to each worktree Git directory.
    class PrivateRecovery
      private

      def existing_identity(git_dir)
        marker = File.join(git_dir, 'shaka-private-id')
        raise Error, "Unsafe worktree identity: #{marker}" if File.symlink?(marker)

        read_identity(marker) if File.file?(marker)
      end

      def assigned_identity(git_dir)
        marker = File.join(git_dir, 'shaka-private-id')
        lock = "#{marker}.lock"
        File.open(lock, File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          raise Error, "Unsafe worktree identity: #{marker}" if File.symlink?(marker)

          File.file?(marker) ? read_identity(marker) : create_identity(marker, git_dir)
        end
      rescue SystemCallError => e
        raise Error, "Cannot assign worktree identity at #{marker}: #{e.message}"
      end

      def create_identity(marker, git_dir)
        temporary = File.join(git_dir, "shaka-private-id-pending-#{SecureRandom.hex(8)}")
        write_identity(temporary)
        File.rename(temporary, marker)
        read_identity(marker)
      ensure
        FileUtils.rm_f(temporary) if temporary
      end

      def write_identity(temporary)
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(SecureRandom.hex(32))
          file.fsync
        end
      end

      def read_identity(marker)
        identity = File.read(marker).strip
        raise Error, "Invalid worktree identity at #{marker}" unless identity.match?(/\A[0-9a-f]{64}\z/)

        identity
      end
    end
  end
end
