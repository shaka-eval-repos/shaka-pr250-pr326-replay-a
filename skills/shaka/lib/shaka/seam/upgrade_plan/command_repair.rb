# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Content repairs for moved command entry points.
      module CommandRepair
        private

        def repaired_file(old, target, source)
          return source unless old.start_with?("#{PATHS::COMMAND_DIRECTORY}/")

          text = source.fetch('data').unpack1('m0').force_encoding(Encoding::UTF_8)
          repaired, kind = checked_repair(old, text)
          return unless repaired

          @repairs << { 'path' => target, 'kind' => kind } if kind
          source.merge('data' => [repaired.b].pack('m0'))
        end

        def checked_repair(old, text)
          return invalid_script(old, 'executable content is not UTF-8; inspect it manually') unless text.valid_encoding?
          return invalid_script(old, 'unsupported command language; inspect it') unless supported_language?(text)

          repaired, kind = repair_root(text)
          return invalid_script(old, 'ambiguous repository-root calculation; repair it explicitly') unless repaired
          return invalid_script(old, 'invocation-relative dependency') if invocation_relative?(repaired)
          return invalid_script(old, 'old command path; repair it explicitly') if old_path?(repaired)

          [repaired, kind]
        end

        def supported_language?(text)
          shebang = text.lines.first.to_s
          return false unless shebang.start_with?('#!')

          %w[sh bash dash ruby].include?(shebang_command(shebang))
        end

        def shebang_command(shebang)
          words = shebang.delete_prefix('#!').strip.split
          command = File.basename(words.shift.to_s)
          command = File.basename(words.reject { |word| word.start_with?('-') }.first.to_s) if command == 'env'
          command
        end

        def invalid_script(path, message)
          @blockers << "#{path}: #{message} before upgrading"
          nil
        end

        def old_path?(text)
          matching_paths(text).any? || directory_reference?(text) || segmented_reference?(text) ||
            continued_old_path?(text) || alias_reference?(text) || shell_fragmented_reference?(text) ||
            unsupported_path_reference?(text)
        end
      end
    end
  end
end
