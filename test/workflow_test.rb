# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'yaml'
require 'shaka/workflow_config'
require 'shaka/workflow'

class WorkflowConfigTest < Minitest::Test
  PHASE_IDS = %w[intake plan implement verify explain review finish].freeze

  def test_packaged_workflow_has_the_complete_ordered_contract
    config = Shaka::WorkflowConfig.load
    ids = config.fetch('phases').map { |phase| phase.fetch('id') }

    assert_equal 1, config.fetch('version')
    assert_equal PHASE_IDS, ids
    refute_empty config.fetch('always')
    refute_empty config.fetch('code_quality')
  end

  def test_every_packaged_phase_has_instructions_and_a_completion_condition
    config = Shaka::WorkflowConfig.load

    config.fetch('phases').each do |phase|
      assert_operator phase.fetch('body').length, :>, 100
      refute_empty phase.fetch('done_when')
    end
  end

  def test_rejects_duplicate_keys
    source = valid_source.sub("version: 1\n", "version: 1\nversion: 1\n")

    error = assert_raises(Shaka::Error) { Shaka::WorkflowConfig.load(source:) }

    assert_includes error.message, 'duplicate key'
  end

  def test_rejects_unknown_top_level_keys
    data = valid_data.merge('surprise' => true)

    error = assert_raises(Shaka::Error) { Shaka::WorkflowConfig.load(source: YAML.dump(data)) }

    assert_includes error.message, 'unknown workflow key: surprise'
  end

  def test_rejects_missing_or_reordered_phases
    data = valid_data
    data['phases'] = data.fetch('phases').reverse

    error = assert_raises(Shaka::Error) { Shaka::WorkflowConfig.load(source: YAML.dump(data)) }

    assert_includes error.message, PHASE_IDS.join(', ')
  end

  def test_rejects_unknown_phase_keys_and_empty_text
    data = valid_data
    data.fetch('phases').first['extra'] = 'no'
    assert_raises(Shaka::Error) { Shaka::WorkflowConfig.load(source: YAML.dump(data)) }

    data = valid_data
    data.fetch('phases').first['body'] = ' '
    error = assert_raises(Shaka::Error) { Shaka::WorkflowConfig.load(source: YAML.dump(data)) }
    assert_includes error.message, 'phases.intake.body'
  end

  private

  def valid_source = YAML.dump(valid_data)

  def valid_data
    {
      'version' => 1, 'title' => 'Shaka', 'purpose' => 'Deliver one task.',
      'phases' => PHASE_IDS.map do |id|
        { 'id' => id, 'title' => id.capitalize, 'body' => "Do #{id} work.", 'done_when' => "#{id} done." }
      end,
      'always' => 'Keep boundaries.', 'code_quality' => 'Keep code small.'
    }
  end
end

class WorkflowCommandTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  GUIDE_LINK = /\]\(<([^>]+\.md)(?:#([\w-]+))?>\)/

  def test_workflow_command_renders_every_phase_and_boundary
    output, status = Open3.capture2e(COMMAND, 'workflow')

    assert_predicate status, :success?, output
    assert_equal 7, output.scan(/^## \d+\. /).size
    assert_includes output, '## Always'
    assert_includes output, '## Code quality'
    assert_includes output, 'Done when:'
  end

  def test_workflow_uses_resolved_configuration_paths
    output, status = Open3.capture2e(COMMAND, 'workflow')

    assert_predicate status, :success?, output
    assert_includes output, 'run the reported scripts'
    assert_includes output, 'resolved `validate` command'
    refute_includes output, '.agents/bin/validate'
    refute_includes output, '{{'
  end

  def test_workflow_command_rejects_arguments
    output, status = Open3.capture2e(COMMAND, 'workflow', 'candidate.yml')

    refute_predicate status, :success?
    assert_includes output, 'Usage: shaka workflow'
  end

  def test_rendered_guide_links_resolve_to_existing_headings
    output, status = Open3.capture2e(COMMAND, 'workflow')
    links = output.scan(GUIDE_LINK)

    assert_predicate status, :success?, output
    refute_empty links
    links.each do |path, anchor|
      assert File.file?(path), "#{path} is not a guide"
      assert_includes heading_slugs(path), anchor, "#{path} has no heading for ##{anchor}" if anchor
    end
  end

  def test_workflow_rejects_unknown_configuration_token
    workflow = Shaka::Workflow.new([])

    error = assert_raises(Shaka::Error) { workflow.send(:expand, '{{config_missing}}') }

    assert_includes error.message, 'unknown template token'
  end

  private

  def heading_slugs(file)
    File.readlines(file, encoding: 'UTF-8').grep(/\A#+ /).map do |line|
      line.sub(/\A#+ /, '').strip.downcase.gsub(/[^\w\s-]/, '').gsub(/\s+/, '-')
    end
  end
end
