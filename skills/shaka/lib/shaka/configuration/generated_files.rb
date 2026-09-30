# frozen_string_literal: true

require 'yaml'

module Shaka
  module Configuration
    # Reads and writes the fixed files created by seam init and migrate.
    module GeneratedFiles
      def generated_text(root:, path:)
        generated_path!(root, path)
        File.read(path, encoding: 'UTF-8')
      end

      def generated_contract(marker:, data:)
        "# #{marker}\n#{YAML.dump(data)}"
      end

      def create_generated_file(root:, path:, content:, mode:, &)
        generated_path!(root, path)
        create_file(path, content, mode:, &)
      end

      def replace_contract(root:, content:, mode:)
        target = path(root, :CONTRACT)
        tmp = "#{target}.migrate-#{Process.pid}"
        create_file(tmp, content, mode:)
        File.rename(tmp, target)
      ensure
        File.delete(tmp) if tmp && File.file?(tmp)
      end

      private

      def generated_path!(root, path)
        return if Paths::GENERATED_FILES.any? { |relative| Paths.at(root, relative) == path }

        raise Error, "Not a generated configuration path: #{path}"
      end

      def create_file(path, content, mode:)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          yield if block_given?
          file.write(content)
          file.chmod(mode)
        end
      end
    end
  end
end
