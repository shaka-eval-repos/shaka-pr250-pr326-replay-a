# frozen_string_literal: true

require_relative 'test_helper'
require 'yaml'
require 'shaka/enforcement_config'
require 'shaka/enforcement'
require 'shaka/enforcement_coverage'

class EnforcementConfigTest < Minitest::Test
  # The audit's whole value is that it cannot quietly go stale, so these are the two ways it
  # could: the workflow drops the sentence, or the workflow gains a rule nobody classified.
  def test_rejects_a_quote_the_workflow_no_longer_contains
    audit = packaged_audit
    audit.fetch('rules').first['quote'] = 'never do a thing this workflow does not mention'

    error = assert_raises(Shaka::Error) { load_audit(audit) }

    assert_includes error.message, 'quotes text the'
  end

  def test_rejects_a_workflow_rule_no_entry_classifies
    ['Never leave a rule unclassified.', 'Classify a rule only when it is audited.',
     'A new rule must be audited.', 'Do not skip a rule.'].each do |added|
      workflow = Shaka::WorkflowConfig.load
      workflow['code_quality'] += " #{added}"

      error = assert_raises(Shaka::Error) { Shaka::EnforcementConfig.load(workflow:) }

      assert_includes error.message, 'classifies no rule for code_quality'
    end
  end

  # A rule stated outside a phase still binds the agent, so every standing field is scanned
  # and every scanned section can be rendered.
  def test_reports_a_rule_from_every_section_it_scans
    command = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
    output = Open3.capture2e(command, 'enforcement').first.force_encoding(Encoding::UTF_8)
    rules = Shaka::EnforcementConfig.load.fetch('rules')

    Shaka::EnforcementCoverage.sections(Shaka::WorkflowConfig.load).each_key do |id|
      next unless rules.any? { |rule| rule['phase'] == id }

      assert_match(/^## #{Regexp.escape(id.tr('_', ' '))}$/i, output, "#{id} rules have no section")
    end
  end

  def test_scans_every_standing_workflow_field
    Shaka::EnforcementCoverage::STANDING.each do |field|
      workflow = Shaka::WorkflowConfig.load
      workflow[field] += ' Never state a rule here unaudited.'

      error = assert_raises(Shaka::Error) { Shaka::EnforcementConfig.load(workflow:) }

      assert_includes error.message, "classifies no rule for #{field}"
    end
  end

  def test_rejects_a_rule_that_names_no_section
    assert_includes mutated_message { |rules| rules.first.delete('phase') }, 'missing rule'
    assert_includes mutated_message { |rules| rules.first['phase'] = 'intkae' }, 'names no workflow section'
  end

  def test_rejects_two_entries_answering_for_one_sentence
    message = mutated_message do |rules|
      overlapping = rules.first.dup
      overlapping['id'] = 'shadow'
      rules.push(overlapping)
    end

    assert_includes message, 'another rule already covers'
  end

  def test_rejects_an_ambiguous_quote
    workflow = Shaka::WorkflowConfig.load
    workflow['always'] += ' Never push to `main`.'

    error = assert_raises(Shaka::Error) { Shaka::EnforcementConfig.load(workflow:) }

    assert_includes error.message, 'appears twice'
  end

  def test_requires_a_detector_from_a_rule_claiming_code_backs_it
    message = mutated_message { |rules| rules.find { |rule| rule['enforced_by'] == 'code' }.delete('detector') }

    assert_includes message, 'detector must be a non-empty string'
  end

  def test_refuses_a_detector_on_an_agent_enforced_rule
    message = mutated_message do |rules|
      rules.find { |rule| rule['enforced_by'] == 'agent' }['detector'] = 'wishful thinking'
    end

    assert_includes message, 'agent-enforced, so it takes no detector'
  end

  def test_rejects_an_unknown_enforcer_a_duplicate_id_and_an_unknown_key
    assert_includes mutated_message { |rules| rules.first['enforced_by'] = 'vibes' }, 'enforced_by must be'
    assert_includes mutated_message { |rules| rules.push(rules.first.dup) }, 'duplicate rule id'
    assert_includes mutated_message { |rules| rules.first['surprise'] = true }, 'unknown rule'
  end

  def test_rejects_duplicate_keys_and_an_unknown_top_level_key
    source = YAML.dump(packaged_audit).sub("version: 1\n", "version: 1\nversion: 1\n")
    assert_includes assert_raises(Shaka::Error) { load_source(source) }.message, 'duplicate key'

    audit = packaged_audit.merge('surprise' => true)
    assert_includes assert_raises(Shaka::Error) { load_audit(audit) }.message, 'unknown enforcement key'
  end

  private

  def packaged_audit
    YAML.safe_load(File.read(Shaka::EnforcementConfig::PATH, encoding: 'UTF-8'))
  end

  def load_audit(audit) = load_source(YAML.dump(audit))

  def load_source(source) = Shaka::EnforcementConfig.load(source:)

  def mutated_message
    audit = packaged_audit
    yield audit.fetch('rules')
    assert_raises(Shaka::Error) { load_audit(audit) }.message
  end
end

# The packaged audit is the artifact; these read it rather than a fixture.
class PackagedAuditTest < Minitest::Test
  def test_the_packaged_audit_classifies_every_rule_the_packaged_workflow_states
    rules = Shaka::EnforcementConfig.load.fetch('rules')

    refute_empty rules
    assert_equal rules.length, rules.map { |rule| rule.fetch('id') }.uniq.length
    rules.each { |rule| refute_empty rule.fetch('quote').strip }
  end

  # The scan misses restrictive "only ..." rules, so an entry has to be able to classify one
  # the scan never demands. Running candidate code outside its checkout is that kind of rule.
  def test_classifies_a_trust_rule_the_scan_does_not_find
    rule = Shaka::EnforcementConfig.load.fetch('rules').find { |entry| entry['id'] == 'isolated-checkout' }

    refute_nil rule
    refute_match Shaka::EnforcementCoverage::MARKER, rule.fetch('quote')
    assert_equal 'agent', rule.fetch('enforced_by')
  end

  # Half of "Never A or B" is not a rule on its own, so a row states it instead of quoting it.
  def test_states_a_rule_whose_quote_is_not_a_sentence
    stated = Shaka::EnforcementConfig.load.fetch('rules').select { |rule| rule['rule'] }

    refute_empty stated
    stated.each do |rule|
      refute_equal rule.fetch('rule'), rule.fetch('quote')
      assert_includes Shaka::EnforcementCoverage.sections(Shaka::WorkflowConfig.load)
                                                .fetch(rule.fetch('phase')),
                      Shaka::EnforcementCoverage.normalize(rule.fetch('quote'))
    end
  end
end

class EnforcementCommandTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def test_reports_every_audited_rule_under_its_workflow_section
    output, status = report

    assert_predicate status, :success?, output
    assert_equal rules.map { |rule| rule['phase'] }.uniq.length, output.scan(/^## /).size
    assert_equal rules.length, output.scan(/^\| .* \| (?:code|reported|github|agent) \| /).size
  end

  def test_counts_how_many_rules_nothing_but_the_agent_enforces
    output, status = report
    alone = rules.count { |rule| rule['enforced_by'] == 'agent' }

    assert_predicate status, :success?, output
    assert_includes output, "#{rules.length} audited rules"
    assert_includes output, "#{alone} enforced by nothing but the agent."
  end

  # The audit claims less than every imperative rule and nothing about live GitHub settings.
  # Both limits belong in the report a maintainer reads, however the sentences are worded.
  def test_states_the_question_it_answers_and_the_limits_it_has
    output, status = report

    assert_predicate status, :success?, output
    assert_match(/if an agent ignores this rule, does anything fail/i, output)
    Shaka::EnforcementCoverage::MARKER.source.scan(/[a-z ]{2,}/).each do |form|
      assert_includes output, form
    end
    assert_match(/github.*(?:still active|not.*recheck)/im, output)
  end

  # Every answer the audit gives has to be explained where a maintainer reads the rows.
  def test_explains_every_answer_it_gives
    output, status = report

    assert_predicate status, :success?, output
    rules.map { |rule| rule.fetch('enforced_by') }.uniq.each do |answer|
      assert_match(/^- `#{answer}` — \S/, output)
    end
  end

  # A command that only reports a violation must not read as one that refuses it.
  def test_separates_a_reported_violation_from_a_refused_one
    output, status = report
    reported = rules.find { |rule| rule['enforced_by'] == 'reported' }

    assert_predicate status, :success?, output
    assert_includes output, "| #{reported['rule'] || reported.fetch('quote')} | reported |"
  end

  # A command that reads only the fields an agent sends it answers nothing, so the audit has
  # to leave it agent-enforced however solid its own validation looks.
  def test_treats_a_self_reported_gate_as_agent_enforced
    checkpoint = rules.find { |rule| rule['id'] == 'checkpoint-proceed' }

    assert_equal 'agent', checkpoint.fetch('enforced_by')
    refute_empty checkpoint.fetch('note').strip
  end

  def test_shows_each_agent_enforced_rule_with_what_is_missing
    output, status = report
    alone = rules.select { |rule| rule['enforced_by'] == 'agent' }

    assert_predicate status, :success?, output
    alone.each { |rule| assert_includes output, "| #{rule['rule'] || rule.fetch('quote')} | agent |" }
  end

  # The report gets pasted into issues, so it must not carry the path of the machine that ran it.
  def test_names_its_source_without_naming_this_machine
    output, status = report

    assert_predicate status, :success?, output
    assert_includes output, 'skills/shaka/config/enforcement.yml'
    refute_includes output, File.expand_path('..', __dir__)
  end

  # A cell that escaped its pipe but not its backslash would let text ending in one split the
  # row and move a column's content into the next. CodeQL found it; this keeps it found.
  def test_a_cell_cannot_break_out_of_its_column
    assert_equal 'a\\|b', Shaka::Enforcement.cell('a|b')
    assert_equal 'c\\\\d', Shaka::Enforcement.cell('c\\d')
    assert_equal 'e\\\\\\|f', Shaka::Enforcement.cell('e\\|f')
  end

  def test_rejects_arguments
    output, status = Open3.capture2e(COMMAND, 'enforcement', 'candidate.yml')

    refute_predicate status, :success?
    assert_includes output, 'Usage: shaka enforcement'
  end

  private

  def rules = Shaka::EnforcementConfig.load.fetch('rules')

  # The report is UTF-8 prose; a POSIX locale would otherwise hand the test binary bytes.
  def report
    output, status = Open3.capture2e(COMMAND, 'enforcement')
    [output.force_encoding(Encoding::UTF_8), status]
  end
end
