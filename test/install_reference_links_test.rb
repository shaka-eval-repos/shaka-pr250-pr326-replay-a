# frozen_string_literal: true

require_relative 'test_helper'

class InstallReferenceLinksTest < Minitest::Test
  def test_local_skill_links_stay_inside_the_copied_skills
    skills = File.expand_path('../skills', __dir__)
    %w[shaka rct mct-claude rct-claude].each { |name| assert_skill_links(skills, name) }
  end

  private

  def assert_skill_links(skills, name)
    skill = File.join(skills, name)
    copied_roots = [skill]
    copied_roots << File.join(skills, 'shaka') unless name == 'shaka'
    Dir.glob('**/*.md', base: skill).each do |relative|
      path = File.join(skill, relative)
      markdown_targets(File.read(path)).each do |target|
        assert_link_in_copied_roots(path, target, copied_roots)
      end
    end
  end

  def assert_link_in_copied_roots(path, target, copied_roots)
    resolved = File.expand_path(target, File.dirname(path))
    assert copied_roots.any? { |root| resolved.start_with?("#{root}/") },
           "#{path}: link escapes the selected install: #{target}"
    assert_path_exists resolved
  end

  def markdown_targets(text)
    text.gsub(/```.*?```/m, '').scan(/\]\(([^)\s]+)\)/).flatten.filter_map do |target|
      value = target.delete_prefix('<').delete_suffix('>').split('#', 2).first
      value unless value.nil? || value.empty? || value.match?(%r{\A(?:[a-z][\w+.-]*:|/)})
    end
  end
end
