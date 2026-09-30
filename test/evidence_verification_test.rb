# frozen_string_literal: true

require_relative 'evidence_fixture'

class EvidenceVerificationTest < Minitest::Test
  include EvidenceFixture

  def test_missing_results_are_not_ready
    with_checkout do |root, ref|
      verdict = verify(root, ref)
      assert_equal 'not_ready', verdict.fetch('status')
      assert_equal %w[validation review], verdict.fetch('missing')
    end
  end

  def test_matching_validation_and_review_results_are_ready
    with_checkout do |root, ref|
      validation = run_check(root, ref, command: 'validate')
      review = review_check(root, ref)
      with_results(validation:, review:) do |paths|
        verdict = verify(root, ref, **paths)
        assert_equal 'ready', verdict.fetch('status')
        statuses = verdict.fetch('checks').values.map { |entries| entries.first.fetch('status') }
        assert_equal %w[bound bound], statuses
      end
    end
  end

  def test_superseded_validation_blocks_readiness
    with_checkout do |root, ref|
      validation = run_check(root, ref, command: 'validate')
      review = review_check(root, ref)
      File.write(File.join(root, '.agents/bin/validate'), "#!/bin/sh\nexit 1\n")
      with_results(validation:, review:) do |paths|
        verdict = verify(root, ref, **paths)
        assert_equal 'not_ready', verdict.fetch('status')
        assert_equal 'superseded', verdict.fetch('checks').fetch('validation').first.fetch('status')
      end
    end
  end

  def test_validate_with_arguments_cannot_satisfy_repository_validation
    with_checkout do |root, ref|
      validation = run_check(root, ref, command: 'validate', arguments: ['test/one_test.rb'])
      with_results(validation:, review: review_check(root, ref)) do |paths|
        reasons = verify(root, ref, **paths).fetch('checks').fetch('validation').first.fetch('reasons')
        assert_includes reasons, 'repository validation used command arguments'
      end
    end
  end

  private

  def verify(root, head, **paths)
    args = ['verify', '--root', root, '--ref', head, '--repository', 'shakacode/shaka', '--head', head]
    paths.each { |kind, path| args.push("--#{kind}", path) }
    output, = capture_io { Shaka::Evidence::Command.run(args) }
    JSON.parse(output)
  end

  def with_results(validation:, review:)
    Tempfile.create(['shaka-validation-', '.json']) do |validation_file|
      Tempfile.create(['shaka-review-', '.json']) do |review_file|
        validation_file.write(JSON.generate(validation))
        review_file.write(JSON.generate(review))
        validation_file.flush
        review_file.flush
        yield validation: validation_file.path, review: review_file.path
      end
    end
  end
end
