# frozen_string_literal: true

module Shaka
  # Lock the sidecar rather than the ledger inode, which atomic replacement changes.
  module LocalReviewLedgerStorage
    private

    def data
      @data ||= if File.exist?(@path)
                  parsed = JSON.parse(File.read(@path, encoding: 'UTF-8'))
                  raise Error, "#{@path} is not a review ledger." unless
                    parsed.is_a?(Hash) && parsed['rounds'].is_a?(Array) && parsed.fetch('pending', []).is_a?(Array)

                  parsed
                else
                  { 'rounds' => [] }
                end
    end

    def locked
      File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        @data = nil
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def pending_without_reservation
      data.fetch('pending', []).reject { |entry| entry['token'] == @reservation }
    end

    def write(content)
      temporary = "#{@path}.#{Process.pid}.#{SecureRandom.hex(8)}.tmp"
      File.write(temporary, "#{JSON.pretty_generate(content)}\n", perm: 0o600)
      File.rename(temporary, @path)
      @data = content
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end
end
